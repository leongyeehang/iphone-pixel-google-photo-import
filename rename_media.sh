#!/usr/bin/env bash
# rename_media.sh: Batch rename photos and videos by timestamp with fallbacks
# Usage: ./rename_media.sh [--dry-run] [target_directory]

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: rename_media.sh [--dry-run] [target_directory]

Batch-rename photos and videos to YYYYMMDD_HHMMSS by EXIF timestamp (with fallbacks),
using exiftool. A %-c counter disambiguates same-timestamp collisions. Runs on the
current directory if no target is given.

Options:
  --dry-run     Preview the renames (exiftool -testname); make no changes.
  -h, --help    Show this help and exit.
EOF
}

# Defaults
DRY_RUN=false
TARGET_DIR=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      TARGET_DIR="$1"
      shift
      ;;
  esac
done

# If TARGET_DIR is not set by a command-line argument, default to current directory
if [[ -z "$TARGET_DIR" ]]; then
    TARGET_DIR="$(pwd)"
fi

# Check for exiftool
if ! command -v exiftool &> /dev/null; then
  echo "Error: exiftool is not installed. Please install it via 'brew install exiftool'." >&2
  exit 1
fi

# Check if the target directory exists
if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: Directory '$TARGET_DIR' not found." >&2
    exit 1
fi

# Put logs in hidden subdirectory to avoid being copied by motionphoto2
WORK_DIR="$TARGET_DIR/.workflow"
mkdir -p "$WORK_DIR"
LOG_FILE="$WORK_DIR/rename.log"
ERROR_LOG="$WORK_DIR/rename_errors.log"

echo "Running batch rename in: $TARGET_DIR" | tee "$LOG_FILE"
if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run mode: no changes will be made" | tee -a "$LOG_FILE"
fi

# Use -testname for dry-run (previews renames), -FileName for actual rename
if [[ "$DRY_RUN" == true ]]; then
    TAG="testname"
else
    TAG="FileName"
fi

# Clear previous error log
: > "$ERROR_LOG"

# NOTE: exiftool applies tags in order — the LAST matching tag wins.
# So the most preferred (accurate) tag must be listed LAST.

echo "--- Renaming videos (.MOV, .MP4, .MTS) ---" | tee -a "$LOG_FILE"
exiftool \
  -ext MOV -ext MP4 -ext MTS "-${TAG}<FileModifyDate" \
  -ext MOV -ext MP4 -ext MTS "-${TAG}<FileCreateDate" \
  -ext MOV -ext MP4 -ext MTS "-${TAG}<TrackCreateDate" \
  -ext MOV -ext MP4 -ext MTS "-${TAG}<MediaCreateDate" \
  -ext MOV -ext MP4 -ext MTS "-${TAG}<QuickTime:CreateDate" \
  -d '%Y%m%d_%H%M%S%%-c.%%e' \
  "$TARGET_DIR" 2>> "$ERROR_LOG" | tee -a "$LOG_FILE" || true

echo "" | tee -a "$LOG_FILE"
echo "--- Renaming photos (.JPG, .JPEG, .HEIC, .DNG) ---" | tee -a "$LOG_FILE"
exiftool \
  -ext jpg -ext jpeg -ext heic -ext dng "-${TAG}<FileCreateDate" \
  -ext jpg -ext jpeg -ext heic -ext dng "-${TAG}<DateTimeCreated" \
  -ext jpg -ext jpeg -ext heic -ext dng "-${TAG}<XMP:CreateDate" \
  -ext jpg -ext jpeg -ext heic -ext dng "-${TAG}<CreateDate" \
  -ext jpg -ext jpeg -ext heic -ext dng "-${TAG}<DateTimeOriginal" \
  -d '%Y%m%d_%H%M%S%%-c.%%e' \
  "$TARGET_DIR" 2>> "$ERROR_LOG" | tee -a "$LOG_FILE" || true

# Error summary
if [[ -s "$ERROR_LOG" ]]; then
    error_count=$(wc -l < "$ERROR_LOG" | tr -d ' ')
    echo "" | tee -a "$LOG_FILE"
    echo "Warning: $error_count error(s) encountered. See $ERROR_LOG for details." | tee -a "$LOG_FILE"
else
    echo "" | tee -a "$LOG_FILE"
    echo "Done. No errors encountered." | tee -a "$LOG_FILE"
    rm -f "$ERROR_LOG"
fi
