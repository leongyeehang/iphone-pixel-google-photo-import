#!/usr/bin/env bash
# rename_media.sh: Batch-rename photos and videos by timestamp with fallbacks.
# Usage: ./rename_media.sh [--dry-run] [target_directory]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" || { echo "Error: lib.sh not found next to $0" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: rename_media.sh [--dry-run] [target_directory]

Batch-rename photos and videos to YYYYMMDD_HHMMSS by EXIF timestamp (with fallbacks),
using exiftool. A %-c counter disambiguates same-timestamp collisions. Runs on the
current directory if no target is given. Renames files IN PLACE.

Extensions and date-tag chains come from lib.sh (override via PHOTO_IMAGE_EXTS /
PHOTO_VIDEO_EXTS / PHOTO_DATE_TAGS / PHOTO_VIDEO_DATE_TAGS).

Options:
  --dry-run     Preview the renames (exiftool -testname); make no changes.
  -h, --help    Show this help and exit.
      --version Print version and exit.
EOF
}

DRY_RUN=false
TARGET_DIR=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    --version) echo "rename_media.sh $WORKFLOW_VERSION"; exit 0 ;;
    *) TARGET_DIR="$1"; shift ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then TARGET_DIR="$(pwd)"; fi

if ! command -v exiftool &> /dev/null; then
  echo "Error: exiftool is not installed. Install via 'brew install exiftool' (macOS) or 'apt-get install libimage-exiftool-perl' (Linux)." >&2
  exit 1
fi

if [[ ! -d "$TARGET_DIR" ]]; then
    echo "Error: Directory '$TARGET_DIR' not found." >&2
    exit 1
fi

if [[ "$DRY_RUN" == true ]]; then
    WORK_DIR="$(mktemp -d)"
    trap 'rm -rf "$WORK_DIR"' EXIT
    TAG="testname"
else
    WORK_DIR="$TARGET_DIR/.workflow"
    mkdir -p "$WORK_DIR"
    TAG="FileName"
fi
LOG_FILE="$WORK_DIR/rename.log"
ERROR_LOG="$WORK_DIR/rename_errors.log"

echo "Running batch rename in: $TARGET_DIR" | tee "$LOG_FILE"
[[ "$DRY_RUN" == true ]] && echo "Dry run mode: no changes will be made" | tee -a "$LOG_FILE"
: > "$ERROR_LOG"

# NOTE: exiftool applies tags in order — the LAST matching tag wins — so the tag
# lists in lib.sh are ordered lowest-priority first. Each tag assignment must be
# preceded by the full -ext list for its media class.
video_args=()
for t in $PHOTO_VIDEO_DATE_TAGS; do
    for e in $PHOTO_VIDEO_EXTS; do video_args+=(-ext "$e"); done
    video_args+=("-${TAG}<$t")
done
photo_args=()
for t in $PHOTO_DATE_TAGS; do
    for e in $PHOTO_IMAGE_EXTS; do photo_args+=(-ext "$e"); done
    photo_args+=("-${TAG}<$t")
done

echo "--- Renaming videos ---" | tee -a "$LOG_FILE"
exiftool "${video_args[@]}" -d '%Y%m%d_%H%M%S%%-c.%%e' "$TARGET_DIR" 2>> "$ERROR_LOG" | tee -a "$LOG_FILE" || true

echo "" | tee -a "$LOG_FILE"
echo "--- Renaming photos ---" | tee -a "$LOG_FILE"
exiftool "${photo_args[@]}" -d '%Y%m%d_%H%M%S%%-c.%%e' "$TARGET_DIR" 2>> "$ERROR_LOG" | tee -a "$LOG_FILE" || true

if [[ -s "$ERROR_LOG" ]]; then
    error_count=$(wc -l < "$ERROR_LOG" | tr -d ' ')
    echo "" | tee -a "$LOG_FILE"
    echo "Warning: $error_count error(s) encountered. See $ERROR_LOG for details." | tee -a "$LOG_FILE"
else
    echo "" | tee -a "$LOG_FILE"
    echo "Done. No errors encountered." | tee -a "$LOG_FILE"
    [[ -f "$ERROR_LOG" ]] && rm -f "$ERROR_LOG"
fi
