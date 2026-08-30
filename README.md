# Photo Import & Organize Workflow

![CI](https://github.com/leongyeehang/iphone-pixel-google-photo-import/actions/workflows/ci.yml/badge.svg)

Batch-organize a folder of photos and videos in up to three steps:

1. **(optional) Mux** — fuse iPhone **Live Photos** (`IMG_1234.JPG` + `IMG_1234.MOV`) into a single Google **Motion Photo**, so the motion survives on Android / Google Photos.
2. **Rename** — rename every file to `YYYYMMDD_HHMMSS` by its real capture date (read from EXIF).
3. **(optional) Group** — pack everything into size-limited, date-named folders (e.g. `250426-260414-14.5GB/`) for transfer in manageable batches.

Every step is optional, so the tool is useful whether you're an iPhone user preparing a Google-Photos backup **or** anyone who just wants their photos renamed by date and/or split into folders.

> **This README documents the *tool*.** For the full end-to-end procedure — iPhone → Image
> Capture → this script → Pixel 1 → Google Photos — see:
> - **[docs/CHECKLIST.md](docs/CHECKLIST.md)** — the one-page tick-list you follow while doing an import.
> - **[docs/WORKFLOW.md](docs/WORKFLOW.md)** — the reference: why each step exists, what to verify, and how to recover when something goes wrong.

> **Origin:** originally built for an iPhone → Google Pixel 1 workflow (Pixel 1 gets free unlimited original-quality Google Photos backup). It has been generalized so anyone can use it — the iPhone→Pixel flow is just one example below.

## Requirements

| Need | For | Install |
|------|-----|---------|
| **bash** ≥ 3.2 + `find`/`stat`/`date`/`awk` | everything | pre-installed on macOS & Linux |
| **[exiftool](https://exiftool.org/)** | rename & group (steps 2–3) | macOS: `brew install exiftool` · Debian/Ubuntu: `sudo apt-get install libimage-exiftool-perl` |
| **[motionphoto2](https://github.com/PetrVys/MotionPhoto2/releases)** | muxing only (step 1) | download the release binary, `chmod +x`, put it on your `PATH` |

If you don't have iPhone Live Photos, run with `--skip-mux` and you won't need `motionphoto2` at all.

As of v1.1, you don't even need `--skip-mux` to avoid a hard failure: if `motionphoto2` isn't installed, `masterscript.sh` detects that automatically, prints a warning, skips muxing, and continues with rename/group. Muxing is no longer required to run the tool at all.

Developed and used on **macOS**; Linux support is built in (portable `date`/`stat`/`df` branches) and exercised in CI. On Windows, use WSL.

## Quick start

```sh
# Full pipeline: mux Live Photos -> rename by date -> group into 15G folders
./masterscript.sh /path/to/photos

# Just rename a folder of photos/videos by date (no iPhone, no motionphoto2 needed):
./masterscript.sh --skip-mux --skip-group /path/to/photos

# Rename + split into 50 GB folders, no muxing:
./masterscript.sh --skip-mux --size 50G /path/to/photos

# Preview the whole thing first — changes nothing:
./masterscript.sh --dry-run /path/to/photos
```

Run it from anywhere — the script resolves its own location. Omit the directory to use the current one. If interrupted, just re-run the same command; it resumes from where it stopped.

## Options — `masterscript.sh`

```
--skip-mux        Skip Live-Photo muxing (step 1). Rename/group then operate on a COPY
                  in <output-name>/ by default (originals untouched). Use --in-place for
                  the old in-place behavior.
--skip-rename     Skip the rename step (step 2).
--skip-group      Skip the size-grouping step (step 3).
--size SIZE       Group folder size (default 15G). Accepts K/M/G, e.g. 50G, 500M.
--output-name N   Name of the muxing output subfolder (default: muxed-photo).
--dry-run         Preview rename/group without changing anything. (Muxing cannot be
                  previewed, so it is skipped in dry-run mode.)
--in-place        When muxing does not run, rename/group the ORIGINALS in place
                  (no output copy). Default is to work on a copy in <output-name>/.
--ledger PATH     Append a per-import summary row to PATH. Precedence: --ledger, then
                  PHOTO_LEDGER, then the default library-ledger.tsv inside the results
                  directory.
--no-ledger       Do not write a ledger row for this run.
-h, --help        Show help and exit.
    --version     Print version and exit.
```

Each step is also a standalone script (all support `-h/--help` and `--version`):

```sh
./run_mux_motionphoto.sh [--output-name NAME] <dir>
./rename_media.sh        [--dry-run] <dir>
./group_files_size.sh    [--dry-run] [--size SIZE] <dir>
./ungroup.sh             <dir>          # reverse a grouping, to re-group differently
```

And one helper that is not part of the pipeline:

```sh
./tools/log_upload.sh [--pushed DATE] [--confirmed DATE] [--log PATH] <batch_dir> [notes]
```

Appends a row to `upload-log.md` recording that a batch has been confirmed backed up. It
reads the batch name, its import folder and its file count from the directory and stamps
today's date. **It detects nothing** — whether the upload finished is something only you can
establish, by checking the service. This just saves you formatting the row by hand. See
[Recording confirmed uploads](#recording-confirmed-uploads).

## Recording confirmed uploads

The per-run `library-ledger.tsv` records what the toolkit **produced**. It cannot record what
your backup service actually **received** — the scripts run on your computer, the upload
happens elsewhere. That gap matters, because it is the gap you are standing in every time you
delete a local copy.

So the confirmation is manual, kept in an `upload-log.md` you own:

```markdown
| Batch | Import | Files | Pushed | Backup confirmed | Notes |
|---|---|---|---|---|---|
| 260415-260503-9.8GB | 2026July28 | 1204 | 2026-08-30 | 2026-08-31 | motion verified |
```

Add a row once a batch is confirmed, *before* you reclaim the space. `tools/log_upload.sh`
will write the row for you; typing it by hand works just as well. The Notes column is free
text and entirely optional.

## Configuration

Every tunable has a built-in default that reproduces the author's current iPhone → Pixel
behavior, defined once in `lib.sh` using the bash idiom `: "${VAR:=default}"`. Override any
of them per run via an environment variable, without touching a file:

**Precedence (highest wins): command-line flag → environment variable → built-in default.**

| Variable | Default | Overrides |
|---|---|---|
| `PHOTO_GROUP_SIZE` | `15G` | grouped-folder size cap (same as `--size`) |
| `PHOTO_OUTPUT_NAME` | `muxed-photo` | mux/copy output subfolder name (same as `--output-name`) |
| `PHOTO_IMAGE_EXTS` | `jpg jpeg heic heif dng png tif tiff gif bmp webp` | recognized image extensions (rename & group) |
| `PHOTO_VIDEO_EXTS` | `mov mp4 m4v avi 3gp 3g2 mts m2ts mkv wmv` | recognized video extensions (rename & group) |
| `PHOTO_DATE_TAGS` | `FileModifyDate FileCreateDate DateTimeCreated XMP:CreateDate CreateDate DateTimeOriginal` | exiftool tag chain used for photo dates |
| `PHOTO_VIDEO_DATE_TAGS` | `FileModifyDate FileCreateDate TrackCreateDate MediaCreateDate QuickTime:CreateDate Keys:CreationDate` | exiftool tag chain used for video dates |
| `PHOTO_LEDGER` | *(empty → `<target>/library-ledger.tsv`)* | ledger file path (same as `--ledger`) |

Example — group into 50 GB folders and name the output `organized/` instead of `muxed-photo/`:

```sh
PHOTO_GROUP_SIZE=50G PHOTO_OUTPUT_NAME=organized ./masterscript.sh /path/to/photos
```

**No config file, by design.** Every default lives once, in `lib.sh`. There is nothing to
create, locate, or keep in sync — export a variable (or inline it before the command) and it
takes effect immediately. If a config file is ever added later, it will be a plain
`KEY=VALUE` file sourced by `lib.sh` reusing these same variable names — never YAML/TOML/JSON.

**Intentionally fixed, not configurable:**
- The grouped-folder name pattern `YYMMDD-YYMMDD-#.#GB` is a hard-coded constant
  (`GROUP_FOLDER_GLOB` in `lib.sh`) — `group_files_size.sh` *creates* folders matching it and
  `ungroup.sh` *globs* that exact pattern to reverse a grouping. A customizable pattern would
  silently break `ungroup.sh`, so it isn't exposed via flag or env var.
- The **order** of the EXIF tag chains is load-bearing application logic, not just a default:
  exiftool applies `-DateTimeOriginal<TAG`-style assignments in sequence and the **last
  matching tag wins**. You can override *which* tags are tried via `PHOTO_DATE_TAGS` /
  `PHOTO_VIDEO_DATE_TAGS`, but the shipped order is guaranteed correct (least-accurate tag
  first, most-accurate last) — if you customize the list, keep your most-trusted tag last.

## Behavior changes in v1.1

- **Broader renaming.** Every recognized media type (see `PHOTO_IMAGE_EXTS` /
  `PHOTO_VIDEO_EXTS` above — screenshots/`.png`, `.tiff`, `.webp`, etc.) is now renamed, not
  just grouped. Previously only `.jpg .jpeg .heic .dng .mov .mp4 .mts` were renamed, so
  anything else could end up grouped into a batch without ever being renamed.
- **Grouping moves only recognized media.** Stray non-media files (`.txt`, `.pdf`, ...) are
  left in place rather than swept into a batch.
- **Copy-by-default.** `--skip-mux` — and the new graceful mux skip below — now operate on a
  **copy** in `<output-name>/` by default; originals are left untouched. Pass `--in-place` to
  restore the pre-v1.1 behavior (rename/group the originals directly, no copy).
- **Graceful mux skip.** A missing `motionphoto2` binary is now a warning, not a fatal error —
  `masterscript.sh` skips muxing and continues with rename/group on a copy.
- **Filesystem-date fallback for photos (and videos, as before).** A photo whose EXIF has no
  usable date tag (common for some screenshots) now falls back to `FileModifyDate`, so it
  still renames deterministically instead of being skipped. Videos already led with
  `FileModifyDate` in their tag chain, so this fallback behavior is the same for both.
- **New end-of-run summary + ledger.** Every real (non-dry-run) run prints a summary (date
  range, image/video/motion-photo counts, total size, batch count) and appends a row to
  `library-ledger.tsv` inside the target directory. Use `--ledger PATH` / `PHOTO_LEDGER` to
  write it elsewhere, or `--no-ledger` to skip it for one run.
- **Everything overridable.** Group size, output-folder name, recognized extensions, EXIF tag
  chains, and the ledger path can all be overridden by `PHOTO_*` environment variables — see
  [Configuration](#configuration) above. Version bumped to `1.1.0`.

## How each step works

### 1. Mux — `run_mux_motionphoto.sh`
- Runs **first** so original iPhone filenames (`IMG_xxxx`) are intact for Live-Photo pairing.
- Pairs are matched by the embedded `ContentIdentifier` (`--exif-match`), not by filename, then fused into a Motion Photo (video embedded inside the image). Without that flag `motionphoto2` falls back to base-name matching.
- Non-pairs are copied as-is (`--copy-unmuxed`); already-muxed files are detected and skipped.
- **Originals are never modified** — output goes to `<dir>/muxed-photo/` (rename with `--output-name`).
- If `motionphoto2` isn't installed, muxing is skipped gracefully with a warning (see [Behavior changes in v1.1](#behavior-changes-in-v11)) — `masterscript.sh` continues with rename/group on a copy of the originals.

### 2. Rename — `rename_media.sh`
- Batch-renames photos and videos to `YYYYMMDD_HHMMSS` (a `%-c` counter disambiguates same-second collisions), in one exiftool pass per media type.
- Recognized extensions come from `lib.sh` (see [Configuration](#configuration)) — the default is broad, covering everything in a typical camera roll, not just the original `.jpg .jpeg .heic .dng .mov .mp4 .mts` set (screenshots/`.png` included).
- exiftool applies tags in order and the **last matching tag wins**, so the most accurate tag is listed last:
  - **Photos:** `FileModifyDate` › `FileCreateDate` › `DateTimeCreated` › `XMP:CreateDate` › `CreateDate` › `DateTimeOriginal`
  - **Videos:** `FileModifyDate` › `FileCreateDate` › `TrackCreateDate` › `MediaCreateDate` › `QuickTime:CreateDate` › `Keys:CreationDate`
- The video chain ends on `Keys:CreationDate` because the `QuickTime:*` tags store UTC with no offset, while stills are named from local-time `DateTimeOriginal`. Ending on a UTC tag named every video 8 hours away from its still (in UTC+8), skewing batch date ranges and pushing early-morning clips onto the previous day.
- A file with no usable EXIF date tag falls back to `FileModifyDate` (the filesystem date), so a screenshot with only a filesystem date still renames deterministically.
- Renames **in place** in the directory it is given.

### 3. Group — `group_files_size.sh`
- Sorts by capture date and packs files into folders of at most `--size` (default 15G), named `YYMMDD-YYMMDD-#.#GB`.
- Dates come from the `YYYYMMDD_HHMMSS` filename first (so run rename first), falling back to the filesystem creation date.
- A single file larger than the limit forms its own over-limit folder (with a warning).

### Why mux before rename?
Because it removes a single point of failure. With `--exif-match` (which this toolkit always passes), pairing is done by `ContentIdentifier` and filenames don't matter — so renaming first would not, by itself, break anything. But *without* that flag `motionphoto2` matches by base name, and after renaming a pair looks like `20260415_194306.HEIC` (photo, local time) next to `20260415_114306.MOV` (video, UTC): 8 hours apart, no pairs found, every Live Photo silently copied unmuxed. Muxing first keeps both matching paths viable and collapses each pair into a single file, so the later rename can't split anything.

See [docs/WORKFLOW.md](docs/WORKFLOW.md#7-quirks-specific-to-this-library) for why muxed Motion Photos still don't move quite like Live Photos in Google Photos — it's a format limitation, not a muxing fault.

## Recommended workflow (best practice)

Keep your **originals with their original names**, one folder per import date, and let the script do the renaming *after* muxing. Don't rename originals by hand, and don't commit photos to git.

```
~/PhotoLibrary/
    2026-07-20/                    # one import, ORIGINAL names
        IMG_0001.JPG
        IMG_0001.MOV
        ...
        muxed-photo/               # created by masterscript (the result)
            250720-250720-12.3GB/  # a ready-to-transfer batch
    2026-08-10/                    # next import, its own folder
```

Per import:
1. Import into a fresh dated folder (keep `IMG_xxxx` names).
2. *(optional)* copy it as-is to another drive for a second backup: `cp -Rp <folder> /Volumes/Backup/…`
3. Process it: `./masterscript.sh ~/PhotoLibrary/2026-07-20`
4. Transfer the `muxed-photo/…GB/` folders to your target device / upload service.
5. Once the upload is confirmed, you may delete `muxed-photo/` — your originals remain.

One folder per import means files from different days never collide, so no manual renaming is ever needed.

## Output layout

```
<input>/                          # originals, untouched (full pipeline)
<input>/muxed-photo/
    workflow.log                  # consolidated run log
    library-ledger.tsv            # per-import summary row, appended each real run
    YYMMDD-YYMMDD-##.#GB/         # grouped, ready to transfer
        20250426_161449.JPG
        20250426_161744.JPG       # a motion photo (video embedded)
        20260414_235413.MOV
```

With `--skip-mux` (or when `motionphoto2` isn't installed), rename/group operate on a **copy**
in `<output-name>/` by default — originals stay untouched. Pass `--in-place` to rename/move
the originals directly instead (no copy), as in versions before v1.1.

## Resume

All enabled steps are checkpointed in `<input>/.workflow/`. Re-running `masterscript.sh` on the same directory skips already-completed steps and continues. Checkpoints are cleaned up on success. (Dry runs never write checkpoints.)

## Logs

During a real run, logs live in hidden `.workflow/` directories:
- `<input>/.workflow/workflow.log` — consolidated, timestamped
- `<target>/.workflow/rename.log`, `rename_errors.log` — rename details/errors
- `<target>/muxing_errors.log` — muxing errors, if any

On success, `workflow.log` is copied into the results directory and the `.workflow/` directories are removed. Dry runs write no persistent logs.

## Testing

```sh
shellcheck *.sh          # lint (brew install shellcheck)
bats test                # test suite (brew install bats-core)
```

GitHub Actions runs `shellcheck` and the `bats` suite on every push and pull request (see
`.github/workflows/ci.yml`); the badge at the top of this README reflects the current status.

## License

MIT — see [LICENSE](LICENSE). The bundled `MotionPhoto2-main/` tool is a separate MIT-licensed project by Petr Vyskocil (see its own `LICENSE`); this workflow calls the installed `motionphoto2` binary rather than that source.

## Changelog

### Unreleased
- **tools/log_upload.sh (new):** records a confirmed upload as a row in `upload-log.md`,
  reading the batch name, import folder and file count from the batch directory and stamping
  the date. It **confirms nothing** — whether a backup finished is knowable only by checking
  the service, so the operator does that and the script just writes down the result. Covered
  by `test/test_log_upload.bats` (9 tests). See
  [Recording confirmed uploads](#recording-confirmed-uploads).
- **docs:** documented the upload log and how it differs from the automatic
  `library-ledger.tsv` (ledger = what was produced; upload log = what the service confirmed).
  Marked `adb` as optional throughout — OpenMTP and the phone's own UI cover every transfer
  step, which matters on devices without USB debugging. Corrected `WORKFLOW.md` Appendix A:
  the backlog it pointed at (`Import2here/Leong/iphone_photos/`) has been superseded by
  `Import2here/2026July28/`, which contains 10,418 of its 10,472 files.
- **CI:** shellcheck now runs with `-x` over `tools/*.sh` as well as the top-level scripts.
- **lib.sh:** appended `Keys:CreationDate` to `PHOTO_VIDEO_DATE_TAGS`. The chain previously
  ended on `QuickTime:CreateDate`, which Apple stores in **UTC with no offset**, so every
  video was named 8 hours away from its still in UTC+8 — skewing batch date ranges and
  pushing clips shot between 00:00 and 08:00 onto the previous day. It also meant a renamed
  Live Photo pair no longer shared a base name, so `motionphoto2`'s filename-matching
  fallback would have found zero pairs had `--exif-match` ever been dropped. Videos without
  the tag still fall back to the UTC tags.
- **docs:** added [docs/WORKFLOW.md](docs/WORKFLOW.md) (end-to-end runbook with verification
  and recovery) and [docs/CHECKLIST.md](docs/CHECKLIST.md) (one-page tick-list). Corrected the
  "why mux before rename" explanation — pairing is by `ContentIdentifier` under `--exif-match`,
  not by filename. Documented why muxed Motion Photos don't move like Live Photos in Google
  Photos (a format capability gap, not a muxing fault).
- **tests:** added a local-time-vs-UTC rename regression test and a tag-chain ordering contract test.

### 2026-07-23 (v1.1) — universal solution
- **lib.sh (new):** single source of truth for the toolkit — `WORKFLOW_VERSION`, the
  `PHOTO_*` overridable defaults (env idiom: flag → env → built-in default; no config file),
  `is_media_file` / `is_image_file` / `is_video_file`, the shared `GROUP_FOLDER_GLOB`, and
  portable helpers (`stat_size`, `epoch_from_filename_or_fs`, `dir_size_kb`, `parse_size`, ...)
  that were previously duplicated or missing. Every script now sources it.
- **rename_media.sh:** extensions and EXIF tag chains now come from `lib.sh` (broader default
  extension set, e.g. `.png` screenshots, `.tiff`, `.webp`); the photo tag chain gains a
  `FileModifyDate` fallback so a screenshot with only a filesystem date still renames.
- **group_files_size.sh:** file selection switched from "exclude known non-media" to "include
  only `is_media_file`" — closes the screenshot bug (files grouped but never renamed) and is
  why stray non-media files are now left in place instead of swept into a batch.
- **run_mux_motionphoto.sh:** a missing `motionphoto2` binary (or nothing to mux) is no longer
  fatal — it warns and exits 0.
- **masterscript.sh:** treats "no muxer / nothing muxed" as a graceful skip and continues;
  when muxing doesn't run, rename/group now operate on a **copy** in `<output-name>/` by
  default (originals untouched) — added `--in-place` to restore the old in-place behavior.
  Fixed a resume-run disk-space double-count (an existing output copy is now subtracted from
  the input-size estimate). Added an end-of-run summary and a `library-ledger.tsv` row inside
  the target dir, with `--ledger PATH` / `--no-ledger` to control it.
- **All scripts:** version consolidated to `1.1.0` in `lib.sh`.
- Deepened the `bats` suite (env overrides, ledger, copy-vs-in-place, graceful mux skip, PNG
  screenshot renaming, resume checkpoints, ...); added the CI status badge above.

### 2026-07-21 (v4) — generalized for reuse
- **masterscript.sh:** added `--skip-mux`, `--skip-rename`, `--skip-group` (steps are now independently optional), `--size` (passed to grouping), `--output-name`, a whole-pipeline `--dry-run`, and `--version`. `--skip-mux` runs rename/group in place. Fixed an exit-code bug (in-place runs returned 1).
- **group_files_size.sh:** added `--size` (K/M/G suffixes) — the 15 GB limit is no longer hardcoded; oversized-file warning reflects the configured size.
- **run_mux_motionphoto.sh:** added `--output-name`.
- **rename_media.sh:** `--dry-run` no longer creates a `.workflow/` directory in the target (logs go to a temp dir, auto-removed).
- **All scripts:** `--version`; clean `shellcheck` pass.
- Added a `bats` test suite (`test/`) and GitHub Actions CI (`shellcheck` + tests). Generalized this README (and converted it from `README.txt` to `README.md`).

### 2026-07-20 (v3)
- Put the whole script folder under git version control (pristine commit + remote backup) so changes can be rolled back.
- **masterscript.sh:** check the target directory exists before resolving it (friendly error instead of a raw `cd` failure); portable `du -sk`/`df -Pk` disk-space check (dropped the dead duplicate OS branch); added a Step-3 (grouping) resume checkpoint; removes the leftover `muxed-photo/.workflow/` directory on success.
- **group_files_size.sh / ungroup.sh:** replaced `((var++))` with `$((var+1))` to avoid a `set -e` abort when a counter increments from 0; grouping warns on files larger than the limit.
- **All scripts:** added `-h/--help`.
- Removed macOS `.DS_Store` and stale `MotionPhoto2-main/__pycache__` artifacts.
- Fixed README path drift; added a "Recommended Workflow" section; added the MIT LICENSE.

### 2026-04-15 (v2)
- **masterscript.sh:** swapped step order to Mux → Rename → Group; rename now targets `muxed-photo/`; originals never modified.
- **rename_media.sh:** fixed exiftool tag-priority order (last matching tag wins), so the accurate tag (`DateTimeOriginal` / `QuickTime:CreateDate`) is listed last.

### 2026-04-15 (v1)
- **rename_media.sh:** batch mode instead of a per-file loop; `-testname` dry-run; error summary; logs in `.workflow/`.
- **run_mux_motionphoto.sh:** removed debug spam; capture stderr; require a directory argument.
- **group_files_size.sh:** parse dates from renamed filenames first; `--dry-run`; temp-file trap cleanup; error handling on `mv`; exclude logs/hidden files; tab-delimited to handle spaces.
- **masterscript.sh:** `BASH_SOURCE` path resolution; checkpoint resume; disk-space pre-flight; consolidated logging.
