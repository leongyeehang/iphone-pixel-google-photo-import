#!/usr/bin/env bash

# masterscript.sh: Automate the photo workflow (mux → rename → group)
# Usage: ./masterscript.sh [options] [target_directory]
# Supports resume: re-run to skip already-completed steps.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" || { echo "Error: lib.sh not found next to $0" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: masterscript.sh [options] [target_directory]

Batch-organize a folder of photos/videos:
  1. (optional) fuse iPhone Live Photos into Google Motion Photos   [needs motionphoto2]
  2. rename everything to YYYYMMDD_HHMMSS by capture date            [needs exiftool]
  3. (optional) group into size-limited, date-named folders

Runs on the current directory if no target is given. Supports resume: re-run to skip
already-completed steps (checkpoints live in <target>/.workflow/).

Options:
  --skip-mux        Skip Live-Photo muxing (step 1). Rename/group then operate on a COPY
                    in <output-name>/ by default (originals untouched). Use --in-place
                    for the old in-place behavior.
  --skip-rename     Skip the rename step (step 2).
  --skip-group      Skip the size-grouping step (step 3).
  --size SIZE       Group folder size (default 15G). Accepts K/M/G, e.g. 50G, 500M.
  --output-name N   Name of the muxing output subfolder (default: muxed-photo).
  --dry-run         Preview rename/group without changing anything. (Muxing cannot be
                    previewed, so it is skipped in dry-run mode.)
  --in-place        When muxing does not run, rename/group the ORIGINALS in place
                    (no output copy). Default is to work on a copy in <output-name>/.
  --ledger PATH     Append a per-import summary row to PATH (default: a
                    library-ledger.tsv inside the results directory; or PHOTO_LEDGER).
  --no-ledger       Do not write a ledger row for this run.
  -h, --help        Show this help and exit.
      --version     Print version and exit.
EOF
}

# Defaults
DRY_RUN=false
SKIP_MUX=false
SKIP_RENAME=false
SKIP_GROUP=false
IN_PLACE=false
OUTPUT_NAME="$PHOTO_OUTPUT_NAME"
SIZE="$PHOTO_GROUP_SIZE"
INPUT_DIR=""
LEDGER_PATH=""
NO_LEDGER=false

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --version) echo "masterscript.sh $WORKFLOW_VERSION"; exit 0 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --skip-mux) SKIP_MUX=true; shift ;;
    --skip-rename) SKIP_RENAME=true; shift ;;
    --skip-group) SKIP_GROUP=true; shift ;;
    --in-place) IN_PLACE=true; shift ;;
    --ledger)
      LEDGER_PATH="${2:-}"
      [[ -z "$LEDGER_PATH" ]] && { echo "Error: --ledger requires a path" >&2; exit 1; }
      shift 2 ;;
    --no-ledger) NO_LEDGER=true; shift ;;
    --size)
      SIZE="${2:-}"
      [[ -z "$SIZE" ]] && { echo "Error: --size requires a value" >&2; exit 1; }
      shift 2
      ;;
    --output-name)
      OUTPUT_NAME="${2:-}"
      [[ -z "$OUTPUT_NAME" ]] && { echo "Error: --output-name requires a value" >&2; exit 1; }
      shift 2
      ;;
    -*) echo "Error: unknown option '$1'" >&2; usage; exit 1 ;;
    *) INPUT_DIR="$1"; shift ;;
  esac
done

# Resolve the directory where this script lives (for calling sibling scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

INPUT_DIR="${INPUT_DIR:-.}"

# Check the directory exists BEFORE resolving it. Resolving with `cd` on a missing
# directory would abort under `set -e` with a raw error, bypassing the message below.
if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Directory '$INPUT_DIR' not found." >&2
    exit 1
fi
INPUT_DIR="$(cd "$INPUT_DIR" && pwd)"

# Muxing writes files, so it cannot be previewed. In dry-run, treat it as skipped.
DRYRUN_SKIPPED_MUX=false
if [[ "$DRY_RUN" == true && "$SKIP_MUX" == false ]]; then
    SKIP_MUX=true
    DRYRUN_SKIPPED_MUX=true
fi

MUXED_DIR="$INPUT_DIR/$OUTPUT_NAME"

# Checkpoints + consolidated log live in a hidden subdirectory (not used in dry-run).
WORK_DIR="$INPUT_DIR/.workflow"
CHECKPOINT_MUX="$WORK_DIR/.mux_done"
CHECKPOINT_RENAME="$WORK_DIR/.rename_done"
CHECKPOINT_GROUP="$WORK_DIR/.group_done"
if [[ "$DRY_RUN" == true ]]; then
    LOG_FILE=/dev/null
else
    mkdir -p "$WORK_DIR"
    LOG_FILE="$WORK_DIR/workflow.log"
fi

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    if [[ "$DRY_RUN" == true ]]; then
        echo "$msg"
    else
        echo "$msg" | tee -a "$LOG_FILE"
    fi
}

write_summary_and_ledger() {
    local images=0 videos=0 total=0 min_epoch="" max_epoch="" e f
    while IFS= read -r -d '' f; do
        is_media_file "$f" || continue
        total=$((total + 1))
        if is_image_file "$f"; then images=$((images + 1)); else videos=$((videos + 1)); fi
        e=$(epoch_from_filename_or_fs "$f")
        if [[ -z "$min_epoch" ]] || (( e < min_epoch )); then min_epoch=$e; fi
        if [[ -z "$max_epoch" ]] || (( e > max_epoch )); then max_epoch=$e; fi
    done < <(find "$TARGET" -type f ! -name ".*" -print0)

    local date_from="-" date_to="-"
    [[ -n "$min_epoch" ]] && date_from=$(epoch_to_ymd "$min_epoch")
    [[ -n "$max_epoch" ]] && date_to=$(epoch_to_ymd "$max_epoch")

    local batches=0 d
    for d in "$TARGET"/$GROUP_FOLDER_GLOB; do [[ -d "$d" ]] && batches=$((batches + 1)); done

    local total_size_gb
    total_size_gb=$(awk -v kb="$(dir_size_kb "$TARGET")" 'BEGIN {printf "%.1f", kb / (1024*1024)}')

    local motion_photos="-"
    if [[ "$SKIP_MUX" == false ]] && command -v exiftool &> /dev/null; then
        # shellcheck disable=SC2016  # single quotes are exiftool's own -if/-p syntax, not shell expansion
        motion_photos=$(exiftool -q -q -if '$XMP-GCamera:MotionPhoto' -p '1' -r "$TARGET" 2>/dev/null | wc -l | tr -d ' ')
    fi

    log "Summary: $date_from..$date_to | images=$images videos=$videos motion=$motion_photos files=$total size=${total_size_gb}GB batches=$batches"

    if [[ "$NO_LEDGER" == true ]]; then return 0; fi
    local ledger
    if [[ -n "$LEDGER_PATH" ]]; then ledger="$LEDGER_PATH"
    elif [[ -n "$PHOTO_LEDGER" ]]; then ledger="$PHOTO_LEDGER"
    else ledger="$TARGET/library-ledger.tsv"; fi

    if [[ ! -f "$ledger" ]]; then
        printf 'run_completed_at\timport_dir\ttarget_dir\tdate_from\tdate_to\timages\tvideos\tmotion_photos\ttotal_files\ttotal_size_gb\tbatches\n' > "$ledger"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$INPUT_DIR" "$TARGET" "$date_from" "$date_to" \
        "$images" "$videos" "$motion_photos" "$total" "$total_size_gb" "$batches" >> "$ledger"
    log "Ledger updated: $ledger"
}

if [[ "$SKIP_MUX" == true && "$SKIP_RENAME" == true && "$SKIP_GROUP" == true ]]; then
    echo "Nothing to do: all steps skipped." >&2
    exit 0
fi

# Disk-space pre-flight (portable: -k = 1024-byte blocks, -P = single-line output).
input_size_kb=$(dir_size_kb "$INPUT_DIR")
# On a resume, an existing output copy inflates the input measurement — subtract it.
if [[ -d "$MUXED_DIR" ]]; then
    muxed_kb=$(dir_size_kb "$MUXED_DIR")
    input_size_kb=$((input_size_kb - muxed_kb))
    (( input_size_kb < 0 )) && input_size_kb=0
fi
input_size_gb=$(awk -v kb="$input_size_kb" 'BEGIN {printf "%.1f", kb / (1024*1024)}')
free_space_kb=$(df -Pk "$INPUT_DIR" | awk 'NR==2 {print $4}')
free_space_gb=$(awk -v kb="$free_space_kb" 'BEGIN {printf "%.1f", kb / (1024*1024)}')
# A copy is made unless the no-mux path runs in place.
if [[ "$IN_PLACE" == true ]]; then
    required_gb="$input_size_gb"
else
    required_gb=$(awk -v sz="$input_size_gb" 'BEGIN {printf "%.1f", sz * 2}')
fi

log "Starting photo workflow in: $INPUT_DIR"
[[ "$DRY_RUN" == true ]] && log "DRY RUN: no files will be changed."
[[ "$DRYRUN_SKIPPED_MUX" == true ]] && log "Note: muxing cannot be previewed; skipping it in dry-run. Rename/group preview against the input files."
log "Input size: ${input_size_gb}GB | Free space: ${free_space_gb}GB | Estimated need: ${required_gb}GB"

if (( $(awk -v free="$free_space_gb" -v need="$required_gb" 'BEGIN {print (free < need) ? 1 : 0}') )); then
    log "WARNING: Free disk space (${free_space_gb}GB) may not be enough. Need ~${required_gb}GB. Continue at your own risk."
fi

# Graceful mux skip: if the binary is missing and muxing wasn't already skipped,
# downgrade to a skip so non-iPhone users can still run rename/group.
if [[ "$SKIP_MUX" == false ]] && ! command -v motionphoto2 &> /dev/null; then
    log "Note: 'motionphoto2' not found — skipping Live-Photo muxing (step 1)."
    SKIP_MUX=true
fi

# Step 1: Mux Live Photos (before rename to preserve original filenames for matching)
if [[ "$SKIP_MUX" == true ]]; then
    if [[ "$IN_PLACE" == true ]]; then
        log "--- Step 1: Muxing skipped; operating IN PLACE on $INPUT_DIR ---"
        [[ "$DRY_RUN" == false ]] && log "Note: originals in $INPUT_DIR will be renamed/moved."
        TARGET="$INPUT_DIR"
    else
        log "--- Step 1: Muxing skipped; copying media into $MUXED_DIR (originals kept) ---"
        if [[ "$DRY_RUN" == true ]]; then
            TARGET="$INPUT_DIR"
            log "DRY RUN: rename/group preview against the input files."
        else
            mkdir -p "$MUXED_DIR"
            copied=0
            while IFS= read -r -d '' f; do
                is_media_file "$f" || continue
                cp -p "$f" "$MUXED_DIR/" && copied=$((copied + 1))
            done < <(find "$INPUT_DIR" -maxdepth 1 -type f ! -name ".*" -print0)
            log "Copied $copied media file(s) into $MUXED_DIR."
            TARGET="$MUXED_DIR"
        fi
    fi
else
    if [[ -f "$CHECKPOINT_MUX" ]]; then
        log "--- Step 1: Skipping muxing (already completed) ---"
    else
        log "--- Step 1: Converting Live Photos ---"
        "$SCRIPT_DIR/run_mux_motionphoto.sh" --output-name "$OUTPUT_NAME" "$INPUT_DIR" 2>&1 | tee -a "$LOG_FILE"
        touch "$CHECKPOINT_MUX"
        log "--- Step 1: Complete ---"
    fi
    if [[ ! -d "$MUXED_DIR" ]]; then
        log "Error: '$MUXED_DIR' was not created by Step 1. Cannot proceed." >&2
        exit 1
    fi
    TARGET="$MUXED_DIR"
fi

# Step 2: Rename the files (originals in input dir stay untouched unless --skip-mux)
if [[ "$SKIP_RENAME" == true ]]; then
    log "--- Step 2: Rename skipped ---"
elif [[ "$DRY_RUN" == false && -f "$CHECKPOINT_RENAME" ]]; then
    log "--- Step 2: Skipping rename (already completed) ---"
else
    log "--- Step 2: Renaming media files ---"
    if [[ "$DRY_RUN" == true ]]; then
        "$SCRIPT_DIR/rename_media.sh" --dry-run "$TARGET" 2>&1 | tee -a "$LOG_FILE"
    else
        "$SCRIPT_DIR/rename_media.sh" "$TARGET" 2>&1 | tee -a "$LOG_FILE"
        touch "$CHECKPOINT_RENAME"
    fi
    log "--- Step 2: Complete ---"
fi

# Step 3: Group the files into folders
if [[ "$SKIP_GROUP" == true ]]; then
    log "--- Step 3: Grouping skipped ---"
elif [[ "$DRY_RUN" == false && -f "$CHECKPOINT_GROUP" ]]; then
    log "--- Step 3: Skipping grouping (already completed) ---"
else
    log "--- Step 3: Grouping files by size ---"
    if [[ "$DRY_RUN" == true ]]; then
        "$SCRIPT_DIR/group_files_size.sh" --dry-run --size "$SIZE" "$TARGET" 2>&1 | tee -a "$LOG_FILE"
    else
        "$SCRIPT_DIR/group_files_size.sh" --size "$SIZE" "$TARGET" 2>&1 | tee -a "$LOG_FILE"
        touch "$CHECKPOINT_GROUP"
    fi
    log "--- Step 3: Complete ---"
fi

if [[ "$DRY_RUN" == true ]]; then
    log "--- Dry run complete (no changes made) ---"
    exit 0
fi

# Clean up checkpoint files on success
rm -f "$CHECKPOINT_MUX" "$CHECKPOINT_RENAME" "$CHECKPOINT_GROUP"

log "--- Workflow complete ---"
log "Results are in: $TARGET"
log "Full log: $LOG_FILE"

write_summary_and_ledger

# Preserve the consolidated log into the results dir, then clean up work dirs.
cp "$LOG_FILE" "$TARGET/workflow.log" 2>/dev/null || true
rm -rf "$WORK_DIR"
# rename_media.sh writes its own logs into <target>/.workflow/; if that's a different
# directory from WORK_DIR (i.e. muxing ran), remove the leftover too.
if [[ "$TARGET" != "$INPUT_DIR" ]]; then
    rm -rf "$TARGET/.workflow"
fi

exit 0
