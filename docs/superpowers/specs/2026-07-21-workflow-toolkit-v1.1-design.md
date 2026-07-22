# Photo Workflow Toolkit — v1.1: Universal Refinements & Ledger

- **Date:** 2026-07-21 (revised 2026-07-22 for the "universal solution" direction)
- **Status:** Approved design, pending final spec review
- **Version target:** `1.1.0` (from `1.0.0`)

## Context

The toolkit (`masterscript.sh` orchestrating `run_mux_motionphoto.sh` → `rename_media.sh`
→ `group_files_size.sh`, plus `ungroup.sh`) is mature and healthy: shellcheck-clean, 12
passing bats tests, portable macOS/Linux branches. This work refines working code and
**generalizes it into a universal tool** that suits many users — while the *shipped
defaults remain the author's current iPhone→Pixel behavior*.

### Confirmed workflow constraints (do not violate)

- **Pixel sideload is load-bearing.** Batches are sideloaded onto a Pixel and backed up
  *from the device*, which earns free unlimited *original* quality. API/web/rclone uploads
  do **not** get the perk and can strip Motion Photo. → No "upload from the Mac" feature.
  The 15 GB grouping cap is the sideload transfer size.
- **No on-device edits.** No `.aae` sidecars. → No sidecar/edit handling.
- **Organize everything in the roll** (screenshots/`.PNG` included).
- Originals are kept and `muxed-photo/` is regenerable → no automated delete gate.

## Guiding principle

**Defaults unchanged; overrides available.** Every generalization knob defaults to the
current behavior, so an existing run produces the same result. Anyone else can override via
an environment variable or a flag — with **no config file and no new dependency**.

## The configuration mechanism

A new sourced `lib.sh` defines every tunable once, using the bash default-assignment idiom:

```sh
: "${PHOTO_GROUP_SIZE:=15G}"
: "${PHOTO_OUTPUT_NAME:=muxed-photo}"
: "${PHOTO_IMAGE_EXTS:=jpg jpeg heic heif dng png tif tiff gif bmp webp}"
: "${PHOTO_VIDEO_EXTS:=mov mp4 m4v avi 3gp 3g2 mts m2ts mkv wmv}"
```

- The literal RHS **is** the shipped default (today's behavior).
- A user overrides by exporting the var, inlining it (`PHOTO_GROUP_SIZE=50G ./masterscript.sh …`), or passing the matching flag.
- **Precedence (high → low):** command-line flag → environment variable → built-in default in `lib.sh`.
- **No config file** (YAGNI). If ever needed it is a plain `KEY=VALUE` file sourced by
  `lib.sh` reusing these same variable names — never YAML/TOML/JSON, never a merge engine.

Some things stay **code constants** in `lib.sh`, deliberately *not* user-configurable
because they are load-bearing across scripts:
- The EXIF tag-chain **order** (accuracy semantics).
- The `motionphoto2` invocation flags.
- The grouped folder-name pattern `YYMMDD-YYMMDD-#.#GB` — `group_files_size.sh` *creates*
  it and `ungroup.sh` *globs* it to reverse it; free-form config would silently break
  `ungroup`.

## Goals

1. Generalize via the env-idiom override layer while keeping defaults identical.
2. One source of truth for media types so rename and group cannot drift (fixes the
   screenshot bug: files grouped but never renamed).
3. Let a non-iPhone user actually run the tool: **graceful mux skip** instead of a hard
   `exit 1` when `motionphoto2` is absent.
4. Non-destructive by default: when muxing does not run, **work on a copy** (originals
   untouched); `--in-place` opts back into the old disk-saving behavior.
5. Consolidate duplicated portable helpers + version into `lib.sh`.
6. Fix the resume-run disk-space double-count.
7. Add a per-import **summary + ledger** (inside the target dir).
8. Deepen tests; close the CI badge item.

## Non-goals / explicitly rejected (YAGNI)

Config-file subsystem; pluggable muxer (`MUXER_BIN`/`--muxer-args`); user-configurable
folder-name pattern (`--folder-format`); `--recursive`; `count`/`none` grouping modes;
`--timezone` flag; hash/catalog DB; reverse-geocoding; direct-from-Mac upload; `.aae`
handling; automated delete gate.

## Deferred to a later version ("later")

- **Custom filename format (`--name-format`)** — blocked: `group_files_size.sh` recovers
  each file's date by *re-parsing* the `YYYYMMDD_HHMMSS` filename, so a format change
  silently breaks folder dating. Requires first decoupling the grouper to read dates from
  EXIF directly. High-value for universality but a separate, larger piece.
- **Calendar grouping (`--group-by day|month|year`)** — creates folder names `ungroup.sh`
  cannot reverse (its glob is hardcoded), so it drags an `ungroup` change along. No need in
  the iPhone→Pixel flow. If adopted later, ship `day+month+year` together and extend
  `ungroup` in lockstep.
- **Explicit copy-vs-in-place beyond the `--in-place` opt-out** — the v1.1 `--in-place`
  flag covers the immediate need; a richer mode matrix can wait.

## Design

### 1. `lib.sh` — shared foundation + override layer

New file beside the scripts, sourced by each via its own `SCRIPT_DIR`:

```sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" || { echo "Error: lib.sh not found next to $0" >&2; exit 1; }
```

Contents:

- **`WORKFLOW_VERSION="1.1.0"`** — single source; each script's `--version` prints
  `"<script>.sh $WORKFLOW_VERSION"`.
- **Override-able defaults** via `: "${VAR:=default}"`: `PHOTO_GROUP_SIZE` (15G),
  `PHOTO_OUTPUT_NAME` (muxed-photo), `PHOTO_IMAGE_EXTS`, `PHOTO_VIDEO_EXTS`,
  `PHOTO_DATE_TAGS`, `PHOTO_VIDEO_DATE_TAGS`, `PHOTO_LEDGER` (empty ⇒ default target-relative path).
- **`IMAGE_EXTS` / `VIDEO_EXTS`** — resolved from the `PHOTO_*_EXTS` vars; the single source
  of truth for "what is a media file." Default is the **broad** list (per the "everything
  in the roll" decision), overridable to a narrower set.
- **`is_media_file <path>`** — true iff the file's lower-cased extension ∈ `IMAGE_EXTS ∪ VIDEO_EXTS`.
- **`GROUP_FOLDER_GLOB`** — the `[0-9][0-9]…-*GB` pattern, shared by group and `ungroup` (constant).
- **Portable helpers** extracted from `group_files_size.sh`: `stat_size`, `stat_ctime`,
  `epoch_from_filename_or_fs`, `epoch_to_yymmdd`, `epoch_to_ymd`, `dir_size_kb`.

Guard: clear error if `lib.sh` is missing. `# shellcheck source=lib.sh` keeps CI clean.

### 2. Single source of truth for file types

- **rename** builds its two exiftool passes' `-ext` args from `IMAGE_EXTS` (photo tag chain)
  and `VIDEO_EXTS` (video tag chain).
- **group** moves a file iff `is_media_file` is true.

Invariant: **everything group moves is also renamed.** The lists live in one place and
cannot drift.

### 3. `rename_media.sh`

- Extensions come from `lib.sh` (broad default incl. `.png` screenshots, `.tiff`, `.webp`,
  `.m4v`, `.3gp`, …).
- Tag chains come from `PHOTO_DATE_TAGS` / `PHOTO_VIDEO_DATE_TAGS`. The photo default gains
  **`FileModifyDate` appended as the lowest-priority fallback** (videos already have it), so
  a screenshot carrying only a filesystem date still renames deterministically. Last-listed
  tag still wins; order otherwise unchanged.

### 4. `group_files_size.sh`

- File selection switches from "exclude `*.sh`/`*.py`/`*.log`/dotfiles" to "include only
  `is_media_file`". Portable helpers and the folder glob come from `lib.sh`.
- **Behavior change (document):** stray non-media files (`.txt`, `.pdf`) are **left in
  place** rather than swept into a photo batch — safer for a camera-roll workflow.

### 5. `run_mux_motionphoto.sh` + `masterscript.sh` — graceful mux skip & copy-by-default

- **Graceful skip:** a missing `motionphoto2` binary (or a run that muxes no pairs) is no
  longer fatal. `run_mux_motionphoto.sh` warns and exits 0; `masterscript.sh` treats "no
  muxer / nothing muxed" as a skip and continues. So `./masterscript.sh <dir>` never
  hard-errors for a non-iPhone user. **Muxing stays ON by default**; with `motionphoto2`
  present it behaves exactly as today.
- **Copy-by-default when muxing does not run** (explicit `--skip-mux`, or graceful skip):
  the media files (per `is_media_file`) are **copied** into `PHOTO_OUTPUT_NAME/` and
  rename/group operate on that copy; **originals are untouched**. The output folder is named
  `muxed-photo` by default even when nothing was muxed (override with `--output-name` /
  `PHOTO_OUTPUT_NAME`; documented).
- **`--in-place` opt-out:** restores the old behavior — rename/group operate directly on the
  target, no copy, negligible extra disk. A clear "originals will be renamed in place"
  warning is printed.
- **Disk-space pre-flight:** estimate ~2× input whenever a copy is made (mux path *or*
  no-mux copy path); ~1× for `--in-place`. On a **resume** run, subtract an existing
  `PHOTO_OUTPUT_NAME/` from the input size so it is not double-counted (portable subtraction;
  BSD `du` has no `--exclude`).

### 6. Per-import summary + ledger

At the end of a **real** run (not dry-run), after the workflow completes:

- **Print a summary** to console and `workflow.log`:
  `date range · #images · #videos · [#motion-photos] · total files · total size · #batches`.
- **Append one TSV row** to the ledger.

Details:

- **Counting** — scan `TARGET` **recursively** (after grouping the media sit inside the
  `YYMMDD-YYMMDD-*GB/` batch subfolders; a recursive scan also handles the un-grouped case).
  Classify via `is_media_file`; total size via `dir_size_kb "$TARGET"`; batches = count of
  `GROUP_FOLDER_GLOB` subfolders; date range from filenames (`epoch_from_filename_or_fs`).
- **Motion photos:** best-effort — when muxing ran and exiftool is present, count images
  whose `XMP-GCamera:MotionPhoto` tag is set (one batch exiftool query); otherwise omit the
  field. Dropped if it proves slow/unreliable in implementation.
- **Ledger location:** default **inside the target dir** (`"$TARGET/library-ledger.tsv"`) —
  the tool never writes outside the folder it was pointed at. Override with `--ledger PATH`
  or `PHOTO_LEDGER`; disable a single run with `--no-ledger`.
- **Format:** append-only TSV; header row written if the file does not exist. Columns
  (fixed, documented, not configurable):
  `run_completed_at  import_dir  target_dir  date_from  date_to  images  videos  motion_photos  total_files  total_size_gb  batches`.
- **Skipped steps:** grouping skipped ⇒ `batches` = `0`; rename skipped ⇒ date range falls
  back to filesystem dates. **Dry-run:** writes no summary and no ledger.

### 7. CI badge

Verify `ci.yml`'s first GitHub run is green (check the Actions tab over the web; `gh` is not
installed locally). If green, add the status badge atop the README; if private/unverifiable,
add the self-reporting badge and note it.

## New/changed CLI surface (`masterscript.sh`)

- New flags: `--in-place`, `--ledger PATH`, `--no-ledger`.
- New env overrides (all optional): `PHOTO_GROUP_SIZE`, `PHOTO_OUTPUT_NAME`,
  `PHOTO_IMAGE_EXTS`, `PHOTO_VIDEO_EXTS`, `PHOTO_DATE_TAGS`, `PHOTO_VIDEO_DATE_TAGS`,
  `PHOTO_LEDGER`.
- Existing flags unchanged: `--skip-mux/-rename/-group`, `--size`, `--output-name`,
  `--dry-run`, `-h/--help`, `--version`.

## Behavior changes (for the changelog)

1. Screenshots/other non-`{jpg,jpeg,heic,dng,mov,mp4,mts}` media are now **renamed**, not
   just grouped (broad default extension set).
2. Grouping moves **only recognized media**; stray non-media files stay put.
3. `--skip-mux` (and the new graceful mux skip) now **work on a copy** by default —
   originals are no longer renamed in place. Use `--in-place` for the old behavior.
4. Missing `motionphoto2` is now a **warning-and-skip**, not a fatal error.
5. A photo with only a filesystem date now renames (via appended `FileModifyDate`).
6. New end-of-run summary + `library-ledger.tsv` inside the target (opt-out `--no-ledger`).
7. Every default is overridable via `PHOTO_*` env vars. Version → `1.1.0`.

## Testing plan (bats)

- **`is_media_file`** unit test (media accepted; `.txt`/`.sh`/dotfile rejected; case-insensitive).
- **Extension single-source-of-truth**: a `.PNG` screenshot with a set filesystem date is
  renamed to `2*.PNG` (needs exiftool; auto-skip if absent).
- **Folder-naming correctness**: produced folder matches `^[0-9]{6}-[0-9]{6}-[0-9.]+GB$` with
  expected dates.
- **Size-suffix parsing**: `--size 500M`, `--size 2K` threshold correctly.
- **Resume checkpoints** (no external tools): pre-seed `.workflow/.rename_done`, run
  `--skip-mux --skip-group`, assert "Skipping rename (already completed)"; symmetric for group.
- **Copy-by-default vs `--in-place`**: `--skip-mux` leaves originals in place **and** creates
  the output copy; `--skip-mux --in-place` renames originals with no copy.
- **Graceful mux skip**: with `motionphoto2` absent (naturally true in CI), `./masterscript.sh`
  (mux enabled) exits 0, skips muxing with a warning, and still produces output; skipped
  locally where the binary exists (mirrors the exiftool-conditional tests).
- **Env override**: `PHOTO_GROUP_SIZE=…` / `PHOTO_OUTPUT_NAME=…` take effect without a flag.
- **Ledger**: a real run prints a summary and appends one TSV row (+ header) inside the
  target; `--no-ledger` and `--dry-run` write none.

All must keep `shellcheck *.sh` clean and pass in CI.

## Sequencing / rollout

1. `lib.sh` (env idiom, media lists, helpers, version) + its unit tests.
2. Rewire `rename_media.sh` and `group_files_size.sh` onto `lib.sh` (photo `FileModifyDate`
   fallback; `is_media_file` grouping filter).
3. Graceful mux skip in `run_mux_motionphoto.sh`; copy-by-default + `--in-place` +
   disk-space fix in `masterscript.sh`.
4. Summary + ledger (+ `--ledger`/`--no-ledger`) in `masterscript.sh`.
5. Tests to green; shellcheck clean.
6. README (universal usage, env overrides, behavior changes, ledger), changelog `v1.1.0`,
   CI badge.

Work proceeds via `writing-plans` → `executing-plans` with TDD, on branch
`v1.1-refinements-and-ledger`. Pristine rollback point remains `a338dc1`.
