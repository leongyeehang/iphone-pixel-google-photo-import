# Photo Workflow Toolkit — v1.1 Refinements & Ledger

- **Date:** 2026-07-21
- **Status:** Approved design, pending spec review
- **Version target:** `1.1.0` (from `1.0.0`)

## Context

The toolkit (`masterscript.sh` orchestrating `run_mux_motionphoto.sh` → `rename_media.sh`
→ `group_files_size.sh`, plus `ungroup.sh`) is mature and healthy: shellcheck-clean, 12
passing bats tests, portable macOS/Linux branches. This work is a set of **refinements to
working code**, not a rewrite.

### Confirmed workflow constraints (do not violate)

- **Pixel sideload is load-bearing.** Batches are sideloaded onto a Pixel and backed up
  *from the device*, which is what earns free unlimited *original* quality. API/web/rclone
  uploads do **not** get the perk and can strip Motion Photo. → No "upload from the Mac"
  feature. The 15 GB grouping cap is the sideload transfer size.
- **No on-device edits.** The roll is imported as-is; there are no `.aae` sidecars. → No
  sidecar/edit-preservation handling.
- **Organize everything in the roll** (screenshots/`.PNG`, saved images, all media types).
- Originals are kept and `muxed-photo/` is regenerable, so deleting it is low-risk; the
  only irreversible act is clearing the phone. → No automated "verify-before-delete" gate.

## Goals

1. Make **rename** and **group** agree on which files they touch, structurally, so the
   screenshot bug (grouped-but-not-renamed) cannot recur.
2. Consolidate duplicated portable helpers and the version string into one sourced file.
3. Fix the resume-run disk-space double-count.
4. Deepen the test suite over the trickiest logic (naming, size parsing, resume).
5. Close the deferred CI badge item.
6. Add a per-import **summary + running ledger** so the user can audit what has been
   processed before clearing the phone.

## Non-goals / explicitly rejected

- Direct-from-Mac upload (rclone/web/desktop) — breaks the free-unlimited perk.
- `.aae`/edit handling — no on-device edits.
- Automated deletion or a delete-gate — `muxed-photo/` is regenerable; originals are kept.
- Recursion, parallelism, config files, new output formats — no need demonstrated.

## Design

### 1. `lib.sh` — shared foundation

New file `lib.sh` beside the scripts, sourced by each via its own `SCRIPT_DIR`:

```sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" || { echo "Error: lib.sh not found next to $0" >&2; exit 1; }
```

Contents:

- **`WORKFLOW_VERSION="1.1.0"`** — single source; each script's `--version` prints
  `"<script>.sh $WORKFLOW_VERSION"`.
- **`IMAGE_EXTS`** = `jpg jpeg heic heif dng png tif tiff gif bmp webp`
- **`VIDEO_EXTS`** = `mov mp4 m4v avi 3gp 3g2 mts m2ts mkv wmv`
  These two lists are the **single source of truth** for "what is a media file."
- **`is_media_file <path>`** — returns 0 if the file's lower-cased extension is in
  `IMAGE_EXTS ∪ VIDEO_EXTS`. Used by grouping.
- **Portable helpers** extracted from `group_files_size.sh` (currently inlined):
  - `stat_size <file>` — bytes (`stat -f%z` / `stat -c%s`).
  - `stat_ctime <file>` — creation/birth epoch with the Linux `%W==0 → %Y` fallback.
  - `epoch_from_filename_or_fs <file>` — parse `YYYYMMDD_HHMMSS`, else `stat_ctime`.
  - `epoch_to_yymmdd <epoch>` / `epoch_to_ymd <epoch>` — portable `date` formatting.
  - `dir_size_kb <dir>` — `du -sk` first field.

Guard: a clear error if `lib.sh` is missing. `# shellcheck source=lib.sh` keeps CI clean.

### 2. Single source of truth for file types

- **rename** builds its two exiftool passes' `-ext` arguments from `IMAGE_EXTS` (photo tag
  chain) and `VIDEO_EXTS` (video tag chain).
- **group** moves a file iff `is_media_file` returns true.

Invariant guaranteed: **everything group moves is also renamed.** The lists live in one
place, so they cannot drift again.

### 3. `rename_media.sh` changes

- Extensions come from `lib.sh` (adds `.png` screenshots, `.tiff`, `.webp`, `.m4v`,
  `.3gp`, etc.).
- Add **`FileModifyDate` as the final (lowest-priority) fallback to the photo chain**
  (videos already have it), so a screenshot carrying only filesystem dates still renames
  deterministically. Tag priority is unchanged otherwise (last-listed wins).

### 4. `group_files_size.sh` changes

- File selection switches from "exclude `*.sh`/`*.py`/`*.log`/dotfiles" to "include only
  `is_media_file`". Portable helpers now come from `lib.sh`.
- **Behavior change (document in README):** a stray non-media file (e.g. a `.txt`, `.pdf`)
  is now **left in place** rather than swept into a photo batch. For a camera-roll workflow
  this is the safer behavior. Logs and scripts were already excluded.

### 5. `masterscript.sh` — disk-space robustness

The pre-flight `du -sk "$INPUT_DIR"` includes `muxed-photo/`, so a **resume** run
double-counts. Fix: when `$MUXED_DIR` already exists, compute input size as
`dir_size_kb(INPUT) - dir_size_kb(MUXED_DIR)` (portable subtraction; BSD `du` has no
`--exclude`). Fresh runs are unaffected.

### 6. Per-import summary + ledger (`masterscript.sh`)

At the end of a **real** run (not dry-run), after the workflow completes:

- **Print a summary** to console and `workflow.log`:
  `date range · #images · #videos · [#motion-photos] · total files · total size · #batches`.
- **Append one TSV row** to a ledger file.

Details:

- **Counting** — scan `TARGET` **recursively**, because after grouping the media sit
  inside the `YYMMDD-YYMMDD-*GB/` batch subfolders (if grouping was skipped they are at the
  top level; a recursive scan handles both). Images/videos classified via `is_media_file` +
  extension class; total size via `dir_size_kb "$TARGET"`; batches = count of
  `YYMMDD-YYMMDD-*GB/` subfolders; date range from filenames (`epoch_from_filename_or_fs`),
  min/max → `epoch_to_ymd`.
- **Motion photos:** best-effort. When muxing ran **and** exiftool is present, count images
  whose `XMP-GCamera:MotionPhoto`/`MicroVideo` tag is set (one batch exiftool query). If
  exiftool is absent or muxing was skipped, omit the field. (If this proves slow/unreliable
  during implementation, drop it — it is the one optional field.)
- **Ledger location:** default `"$(dirname "$INPUT_DIR")/library-ledger.tsv"` — i.e. the
  library root above the dated import folders, matching the recommended layout. Override
  with `--ledger PATH`; disable a single run with `--no-ledger`.
- **Format:** append-only TSV; write a header row if the file does not yet exist. Columns:
  `run_completed_at  import_dir  target_dir  date_from  date_to  images  videos  motion_photos  total_files  total_size_gb  batches`.
  Hand-editable; never rewritten.
- **Skipped steps:** if grouping was skipped, `batches` = `0`; other fields still computed
  from `TARGET`. If rename was skipped, filename dates may be absent → date range falls
  back to filesystem dates.
- **Dry-run:** writes no summary and no ledger (consistent with "dry runs write nothing").
- **Resume:** each successful completion appends a row; the timestamp disambiguates. A
  re-run of an already-finished import produces a second row (acceptable; noted in README).

New masterscript flags: `--ledger PATH`, `--no-ledger` (add to usage/help + README).

### 7. CI badge

Verify the `ci.yml` workflow's first run on GitHub is green (check the Actions tab over the
web, since `gh` is not installed locally). If green, add the status badge to the top of the
README. If the repo is private / unverifiable, add the self-reporting badge and note it.

## Behavior changes (for the changelog / upgrading users)

1. Screenshots and other non-`{jpg,jpeg,heic,dng,mov,mp4,mts}` media are now **renamed**,
   not just grouped.
2. Grouping now moves **only recognized media**; stray non-media files stay put (previously
   everything non-script/log was moved).
3. New `masterscript.sh` output: an end-of-run summary; a `library-ledger.tsv` at the
   library root (opt-out with `--no-ledger`).
4. Version → `1.1.0`.

## Testing plan (bats)

- **Folder-naming correctness** (`test_group.bats`): for known dated inputs, assert the
  produced folder name matches `^[0-9]{6}-[0-9]{6}-[0-9.]+GB$` with the expected dates.
- **Size-suffix parsing**: `--size 500M` and `--size 2K` threshold correctly.
- **Resume checkpoints** (new, no external tools): pre-seed `.workflow/.rename_done`, run
  `masterscript.sh --skip-mux --skip-group`, assert output contains
  `"Skipping rename (already completed)"`; symmetric test for `.group_done` with
  `--skip-mux --skip-rename`.
- **Screenshot regression** (`test_rename.bats`, needs exiftool, auto-skip if absent):
  a `.PNG` with a set filesystem date is renamed to `2*.PNG`.
- **`is_media_file`** unit test: media extensions accepted, `.txt`/`.sh`/dotfile rejected
  (case-insensitive).
- **Ledger**: after a real `--skip-mux` run, assert a summary line is printed and one TSV
  row (plus header) is appended; `--no-ledger` writes none; `--dry-run` writes none.

All must keep `shellcheck *.sh` clean and pass in CI.

## Sequencing / rollout

1. Add `lib.sh` (helpers + lists + version) with its unit tests.
2. Rewire `rename_media.sh` and `group_files_size.sh` onto `lib.sh`; add the photo
   `FileModifyDate` fallback and the `is_media_file` grouping filter.
3. Disk-space resume fix in `masterscript.sh`.
4. Summary + ledger in `masterscript.sh` (+ `--ledger`/`--no-ledger`).
5. Add/extend tests until green; keep shellcheck clean.
6. README (behavior changes, ledger docs, options), changelog `v1.1.0`, CI badge.

Work proceeds via `writing-plans` → `executing-plans` with TDD. The pristine rollback
point remains `a338dc1`.
