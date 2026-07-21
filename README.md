# Photo Import & Organize Workflow

Batch-organize a folder of photos and videos in up to three steps:

1. **(optional) Mux** — fuse iPhone **Live Photos** (`IMG_1234.JPG` + `IMG_1234.MOV`) into a single Google **Motion Photo**, so the motion survives on Android / Google Photos.
2. **Rename** — rename every file to `YYYYMMDD_HHMMSS` by its real capture date (read from EXIF).
3. **(optional) Group** — pack everything into size-limited, date-named folders (e.g. `250426-260414-14.5GB/`) for transfer in manageable batches.

Every step is optional, so the tool is useful whether you're an iPhone user preparing a Google-Photos backup **or** anyone who just wants their photos renamed by date and/or split into folders.

> **Origin:** originally built for an iPhone → Google Pixel 1 workflow (Pixel 1 gets free unlimited original-quality Google Photos backup). It has been generalized so anyone can use it — the iPhone→Pixel flow is just one example below.

## Requirements

| Need | For | Install |
|------|-----|---------|
| **bash** ≥ 3.2 + `find`/`stat`/`date`/`awk` | everything | pre-installed on macOS & Linux |
| **[exiftool](https://exiftool.org/)** | rename & group (steps 2–3) | macOS: `brew install exiftool` · Debian/Ubuntu: `sudo apt-get install libimage-exiftool-perl` |
| **[motionphoto2](https://github.com/PetrVys/MotionPhoto2/releases)** | muxing only (step 1) | download the release binary, `chmod +x`, put it on your `PATH` |

If you don't have iPhone Live Photos, run with `--skip-mux` and you won't need `motionphoto2` at all.

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
--skip-mux        Skip Live-Photo muxing (step 1). Rename/group then operate IN PLACE
                  on the target directory (no output subfolder is created).
--skip-rename     Skip the rename step (step 2).
--skip-group      Skip the size-grouping step (step 3).
--size SIZE       Group folder size (default 15G). Accepts K/M/G, e.g. 50G, 500M.
--output-name N   Name of the muxing output subfolder (default: muxed-photo).
--dry-run         Preview rename/group without changing anything. (Muxing writes files,
                  so it is skipped in dry-run mode.)
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

## How each step works

### 1. Mux — `run_mux_motionphoto.sh`
- Runs **first** so original iPhone filenames (`IMG_xxxx`) are intact for Live-Photo pairing.
- Pairs are matched by filename **and** by the embedded `ContentIdentifier` (`--exif-match`), then fused into a Motion Photo (video embedded inside the image).
- Non-pairs are copied as-is (`--copy-unmuxed`); already-muxed files are detected and skipped.
- **Originals are never modified** — output goes to `<dir>/muxed-photo/` (rename with `--output-name`).

### 2. Rename — `rename_media.sh`
- Batch-renames photos and videos to `YYYYMMDD_HHMMSS` (a `%-c` counter disambiguates same-second collisions), in one exiftool pass per media type.
- Supported: `.jpg .jpeg .heic .dng .mov .mp4 .mts`
- exiftool applies tags in order and the **last matching tag wins**, so the most accurate tag is listed last:
  - **Photos:** `DateTimeOriginal` › `CreateDate` › `XMP:CreateDate` › `DateTimeCreated` › `FileCreateDate`
  - **Videos:** `QuickTime:CreateDate` › `MediaCreateDate` › `TrackCreateDate` › `FileCreateDate` › `FileModifyDate`
- Renames **in place** in the directory it is given.

### 3. Group — `group_files_size.sh`
- Sorts by capture date and packs files into folders of at most `--size` (default 15G), named `YYMMDD-YYMMDD-#.#GB`.
- Dates come from the `YYYYMMDD_HHMMSS` filename first (so run rename first), falling back to the filesystem creation date.
- A single file larger than the limit forms its own over-limit folder (with a warning).

### Why mux before rename?
A Live Photo is an image + a companion `.MOV` matched by name. If you rename **first**, the photo and video are renamed in separate passes by slightly different timestamps and no longer share a base name — the pair breaks and the motion is lost. Muxing first collapses each pair into a single file, so the later rename can't split anything.

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
    YYMMDD-YYMMDD-##.#GB/         # grouped, ready to transfer
        20250426_161449.JPG
        20250426_161744.JPG       # a motion photo (video embedded)
        20260414_235413.MOV
```

With `--skip-mux`, there is no `muxed-photo/` copy — rename/group happen in place in `<input>/` and originals are renamed/moved.

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

GitHub Actions runs `shellcheck` and the `bats` suite on every push (see `.github/workflows/ci.yml`).

> **Follow-up (deferred):** the CI workflow was added in `59fbd70` but its first run on GitHub hasn't been confirmed yet. Check the repo's **Actions** tab; if it's green, optionally add a status badge at the top of this README:
> `![CI](https://github.com/leongyeehang/iphone-pixel-google-photo-import/actions/workflows/ci.yml/badge.svg)`

## License

MIT — see [LICENSE](LICENSE). The bundled `MotionPhoto2-main/` tool is a separate MIT-licensed project by Petr Vyskocil (see its own `LICENSE`); this workflow calls the installed `motionphoto2` binary rather than that source.

## Changelog

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
