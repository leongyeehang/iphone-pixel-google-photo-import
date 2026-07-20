Description
This master script automates a three-step photo management workflow:

1. Converts iPhone Live Photos (HEIC/JPG) into a Pixel-compatible Google Motion Photo format using motionphoto2.
2. Renames media files based on their creation timestamps to prevent naming conflicts.
3. Groups all processed files into folders of approximately 15GB, organized by date.

Muxing runs BEFORE renaming so that original iPhone filenames (IMG_xxxx) are preserved
for Live Photo pairing. This ensures both filename matching and EXIF matching work reliably.
Original files in the input directory are never modified — all changes happen in muxed-photo/.

This workflow is designed to prepare photos for upload to a Google Pixel 1, leveraging its free unlimited original-quality photo backups.


Dependencies
Install these before running:

- exiftool
    brew install exiftool

- motionphoto2 (standalone binary, NOT a pip package)
    Download from: https://github.com/PetrVys/MotionPhoto2/releases
    On macOS: download the macOS release, then run:
      chmod +x motionphoto2
    Move it somewhere in your PATH (e.g. /usr/local/bin/).

- Standard Unix utilities (find, stat, date, awk) — pre-installed on macOS.


Usage

  Full workflow (mux + rename + group):

    ./masterscript.sh /path/to/your/photos

  The script can be called from any directory — it resolves its own location.
  If you omit the directory path, it runs on the current directory.

  Individual scripts can also be run standalone:

    ./run_mux_motionphoto.sh /path/to/your/photos
    ./rename_media.sh [--dry-run] /path/to/your/photos/muxed-photo
    ./group_files_size.sh [--dry-run] /path/to/your/photos/muxed-photo

  Every script accepts -h/--help to print its own usage, e.g.:

    ./masterscript.sh --help

  Dry-run examples (preview without making changes):

    ./rename_media.sh --dry-run /path/to/your/photos/muxed-photo
        Shows what each file would be renamed to, without actually renaming.

    ./group_files_size.sh --dry-run /path/to/your/photos/muxed-photo
        Shows what folders would be created and how many files in each.


Example: Full Workflow

  1. Import photos from iPhone using Image Capture into a folder:

       /Volumes/Aca_WD/media/Import from Image Capture/2026-04-15/

     The folder contains raw iPhone files like:
       IMG_1136.JPG, IMG_1369.JPG, IMG_1369.MOV, IMG_1370.JPG,
       IMG_1390.MOV, IMG_1405.MOV, IMG_1406.MOV, IMG_1439.MOV, ...

  2. Run the full workflow:

       cd "/Volumes/Aca_WD/media/Import from Image Capture/script"
       ./masterscript.sh "/Volumes/Aca_WD/media/Import from Image Capture/2026-04-15"

     Or from any directory (the script resolves its own path):

       /path/to/script/masterscript.sh "/path/to/imported/photos"

  3. The script runs three steps automatically:

     Step 1 — Mux Live Photos:
       IMG_1369.JPG + IMG_1369.MOV are combined into a single Google Motion Photo.
       Files without a Live Photo pair are copied as-is.
       Original files in the input directory are NOT modified.
       Output goes to: .../2026-04-15/muxed-photo/

     Step 2 — Rename:
       Files in muxed-photo/ are renamed by EXIF timestamp:
       IMG_1136.JPG  -->  20250426_161449.JPG
       IMG_1369.JPG  -->  20250426_161744.JPG  (now a motion photo with embedded video)
       IMG_1406.MOV  -->  20260414_235413.MOV
       ...

     Step 3 — Group by size:
       All files in muxed-photo/ are sorted by date and grouped into ~15GB folders.
       Output: .../2026-04-15/muxed-photo/250426-260414-14.5GB/
               .../2026-04-15/muxed-photo/260414-260415-12.3GB/
               ...

  4. Transfer the grouped folders to your Pixel 1 for backup upload.


Example: Dry-Run Before Processing

  Preview what rename would do (no files changed):

    ./rename_media.sh --dry-run "/path/to/imported/photos/muxed-photo"

    Output:
      'IMG_1136.JPG' --> '20250426_161449.JPG'
      'IMG_1369.JPG' --> '20250426_161744.JPG'
      ...
      0 image files updated (dry run)

  Preview how files would be grouped (no folders created):

    ./group_files_size.sh --dry-run "/path/to/imported/photos/muxed-photo"

    Output:
      [DRY RUN] Would create folder: 250426-260414-14.5GB (320 files, 14.5GB)
      [DRY RUN] Would create folder: 260414-260415-12.3GB (280 files, 12.3GB)
      Dry run complete. Would group 600 files into 2 folder(s).


Example: Resuming After Interruption

  If the workflow fails or is interrupted (e.g. during muxing):

    ./masterscript.sh "/path/to/imported/photos"

    Output:
      --- Step 1: Skipping muxing (already completed) ---
      --- Step 2: Renaming media files ---
      ...

  The script detects which steps already completed and picks up where it left off.


Example: Ungrouping and Re-grouping

  If you want to re-group files (e.g. with a different size limit):

    ./ungroup.sh /path/to/your/photos/muxed-photo
    ./group_files_size.sh /path/to/your/photos/muxed-photo

  ungroup.sh moves all files from YYMMDD-YYMMDD-##.#GB/ subfolders back to muxed-photo/.
  No files are deleted. If a file with the same name already exists, it is skipped with a warning.


Workflow Breakdown

  Step 1: Live Photo Conversion (run_mux_motionphoto.sh)
  - Runs FIRST to preserve original iPhone filenames for reliable pairing.
  - Finds Live Photos (JPG+MOV or HEIC+MOV pairs) and processes them with motionphoto2.
  - Pairs are matched by both filename (IMG_1369.JPG + IMG_1369.MOV) and
    EXIF metadata (--exif-match uses Content Identifier written by iPhone).
  - Creates Google Motion Photo files (video embedded inside the image).
  - Non-Live-Photo files are copied as-is to the output (--copy-unmuxed).
  - Already-muxed motion photos are detected and skipped automatically.
  - Original files in the input directory are never modified.
  - Output goes to: <input_directory>/muxed-photo/

  Step 2: Renaming (rename_media.sh)
  - Operates on muxed-photo/ (not the original input directory).
  - Batch-renames photos and videos to YYYYMMDD_HHMMSS format using EXIF metadata.
  - Uses exiftool in batch mode (processes all files in one call).
  - Supported file types: .jpg, .jpeg, .heic, .dng, .mov, .mp4, .mts
  - Fallback chain for photo timestamps:
      DateTimeOriginal > CreateDate > XMP:CreateDate > DateTimeCreated > FileCreateDate
  - Fallback chain for video timestamps:
      QuickTime:CreateDate > MediaCreateDate > TrackCreateDate > FileCreateDate > FileModifyDate

  Step 3: Grouping Files (group_files_size.sh)
  - Groups processed files into subdirectories of ~15GB each.
  - Folder names based on date range and total size (e.g., 231026-231028-14.5GB).
  - Dates are parsed from renamed filenames (YYYYMMDD_HHMMSS) first,
    falling back to filesystem creation date if the filename doesn't match.
  - Output goes to: <input_directory>/muxed-photo/YYMMDD-YYMMDD-##.#GB/


Why Mux Before Rename?
  - Original filenames (IMG_xxxx) allow both filename AND EXIF matching for Live Photo pairing.
  - Renaming first can cause mismatched counter suffixes when two Live Photos share the
    same timestamp (photos and videos are renamed in separate batches).
  - After muxing, the companion MOV is embedded inside the JPG — fewer files to rename
    and no pairing issues.
  - Original files are never touched — the input directory serves as an untouched backup.


Output Location

  After running masterscript.sh, the final output is:

    <input_directory>/                        <-- originals, untouched
    <input_directory>/muxed-photo/
      workflow.log                            <-- consolidated log
      YYMMDD-YYMMDD-##.#GB/                  <-- grouped folder(s), ready for Pixel transfer
        20250426_161449.JPG
        20250426_161744.JPG                   <-- motion photo (video embedded)
        20260414_235413.MOV
        ...

  The grouped folders inside muxed-photo/ are what you transfer to the Pixel 1.
  Each folder is under 15GB so it can be transferred in manageable batches.


Resume Capability
If the workflow is interrupted (e.g. power loss, Ctrl+C), re-running masterscript.sh
on the same directory will skip already-completed steps and continue from where it left off.
All three steps (mux, rename, group) are checkpointed.
Checkpoint files are stored in <input_directory>/.workflow/ and cleaned up on success.


Logs
Logs are stored in hidden .workflow/ directories during execution:
  - <input_dir>/.workflow/workflow.log        — consolidated timestamped log for all steps
  - <muxed-photo>/.workflow/rename.log         — rename details
  - <muxed-photo>/.workflow/rename_errors.log  — rename errors/warnings if any

After successful completion:
  - workflow.log is copied to muxed-photo/ for reference
  - The .workflow/ directories (in both the input dir and muxed-photo/) are cleaned up

Muxing errors (if any) are logged to:
  - muxed-photo/muxing_errors.log


Changelog

  2026-07-20 (v3)
  - Put the whole script folder under git version control (initial pristine commit +
    remote backup) so changes can be rolled back.
  - masterscript.sh: Check the target directory exists BEFORE resolving it (a bad path
    now shows the friendly error instead of a raw `cd` failure). Rewrote the disk-space
    pre-flight to use portable `du -sk`/`df -Pk` (1024-byte blocks) and dropped the dead
    duplicate OS branch. Added a Step-3 (grouping) resume checkpoint. Also removes the
    leftover muxed-photo/.workflow/ directory on success.
  - group_files_size.sh / ungroup.sh: Replaced ((var++)) with $((var+1)) to avoid a
    `set -e` abort when a counter increments from 0 (harmless on bash 3.2, a real abort
    on newer bash). group_files_size.sh now warns if a single file exceeds the ~15GB
    group limit (it forms its own over-limit folder).
  - All five scripts: Added -h/--help usage output.
  - Removed macOS .DS_Store files and stale MotionPhoto2-main/__pycache__ artifacts.
  - README.txt: Fixed path drift (scriptforphotolatest -> script; dropped the
    non-existent homeServer path segment).

  2026-04-15 (v2)
  - masterscript.sh: Swapped step order to Mux -> Rename -> Group.
    Rename now targets muxed-photo/ instead of input directory.
    Original files are never modified.
  - rename_media.sh: Fixed exiftool tag priority order. In exiftool, the LAST matching
    tag wins, so the most accurate tag (DateTimeOriginal for photos, QuickTime:CreateDate
    for videos) must be listed last. Previously FileCreateDate was last, causing files
    to be renamed with the copy/filesystem date instead of the actual photo date.

  2026-04-15 (v1)
  - rename_media.sh: Replaced per-file exiftool loop with batch mode (much faster).
    Added -testname dry-run support and error summary. Logs moved to .workflow/ directory.
  - run_mux_motionphoto.sh: Removed set -x debug spam. Added stderr capture to log file.
    Removed interactive prompt (always requires directory argument).
    Updated install reference to https://github.com/PetrVys/MotionPhoto2.
  - group_files_size.sh: Dates now parsed from renamed filenames first (YYYYMMDD_HHMMSS),
    falling back to filesystem creation date. Added --dry-run mode. Added trap cleanup for
    temp files. Added error handling on mv operations. Strips ./ prefix. Excludes log and
    hidden files from grouping. Uses tab delimiter to handle filenames with spaces.
  - masterscript.sh: Uses BASH_SOURCE for script path resolution (works from any directory).
    Added checkpoint resume in .workflow/ directory. Added disk space pre-flight check.
    Added consolidated timestamped logging. Validates muxed-photo/ exists before next step.
    Cleans up .workflow/ on success.
