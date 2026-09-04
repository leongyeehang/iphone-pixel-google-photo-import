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

# --- Videos named in UTC instead of local time --------------------------------
# The video tag chain ends on Keys:CreationDate because that tag carries the local time
# plus its UTC offset. A video WITHOUT it falls through to the QuickTime:* tags, which
# store UTC with no offset - so it is named hours from its true local time (8 h in SGT),
# which can push an early-morning clip onto the previous day and into the wrong batch.
# exiftool reports nothing for this: the rename simply SUCCEEDS with the wrong name, so
# without this check the case is invisible. Detection only - the real capture offset is
# not in the file, so the script cannot correct it.
utc_ext_args=()
for e in $PHOTO_VIDEO_EXTS; do utc_ext_args+=(-ext "$e"); done
# exiftool exits 2 when NO file matches -if - which is the GOOD case here. Under pipefail
# that would abort the script, so neutralize the status; empty output still means "none".
# -f is required: it makes a missing tag read as "-" so absence can be tested at all.
# shellcheck disable=SC2016  # single quotes are exiftool's own -if/-p syntax, not shell expansion
utc_named=$( { exiftool -q -q -f "${utc_ext_args[@]}" \
    -if '$Keys:CreationDate eq "-"' \
    -if '$QuickTime:CreateDate ne "-" and $QuickTime:CreateDate ne "0000:00:00 00:00:00"' \
    -p '$FileName' "$TARGET_DIR" 2>/dev/null || true; } | LC_ALL=C sort)

if [[ -n "$utc_named" ]]; then
    utc_count=$(printf '%s\n' "$utc_named" | wc -l | tr -d ' ')
    echo "" | tee -a "$LOG_FILE"
    if [[ "$DRY_RUN" == true ]]; then
        echo "Note: $utc_count video(s) have no Keys:CreationDate and WOULD be named from a UTC" | tee -a "$LOG_FILE"
    else
        echo "Note: $utc_count video(s) have no Keys:CreationDate and were named from a UTC" | tee -a "$LOG_FILE"
    fi
    echo "tag, so their names are offset from local time (8 h in UTC+8). A clip shot before" | tee -a "$LOG_FILE"
    echo "08:00 local therefore carries the previous day's date." | tee -a "$LOG_FILE"
    printf '%s\n' "$utc_named" | head -20 | sed 's/^/  /' | tee -a "$LOG_FILE"
    if [[ "$utc_count" -gt 20 ]]; then
        echo "  ... and $((utc_count - 20)) more" | tee -a "$LOG_FILE"
    fi
    echo "This is not an error and nothing failed; the names are simply in UTC. Fix them by" | tee -a "$LOG_FILE"
    echo "hand if the date matters. See docs/WORKFLOW.md - \"Videos and stills are both named" | tee -a "$LOG_FILE"
    echo "in local time\"." | tee -a "$LOG_FILE"
fi

# exiftool writes BOTH failures and informational notices to stderr, so the line count
# is not an error count. Two notices are routine for this pipeline's OWN correct output:
#   "Google trailer MotionPhoto video/quicktime not handled"  - every muxed JPG Motion Photo
#   "[minor] The ExtractEmbedded option may find more tags"   - every video
# Counting those as errors made a clean run report thousands of them.
echo "" | tee -a "$LOG_FILE"
if [[ -s "$ERROR_LOG" ]]; then
    # Classify by MEANING, not by prefix - see benign_notice_count() in lib.sh.
    notices=$(benign_notice_count "$ERROR_LOG")
    total=$(message_line_count "$ERROR_LOG")
    real_errors=$((total - notices))

    if [[ "$real_errors" -gt 0 ]]; then
        echo "Warning: $real_errors problem(s) encountered. See $ERROR_LOG for details." | tee -a "$LOG_FILE"
        # NB: a bare `[[ ... ]] && echo` here would return 1 when false and trip `set -e`.
        if [[ "$notices" -gt 0 ]]; then
            echo "($notices expected Motion Photo/video notice(s) also logged.)" | tee -a "$LOG_FILE"
        fi
    elif [[ "$notices" -gt 0 ]]; then
        echo "Done. No failures. $notices expected exiftool notice(s) logged." | tee -a "$LOG_FILE"
        echo "(Motion Photo trailers and video ExtractEmbedded hints - both are normal.)" | tee -a "$LOG_FILE"
        echo "See $ERROR_LOG if you want to read them." | tee -a "$LOG_FILE"
    else
        echo "Done. No errors encountered." | tee -a "$LOG_FILE"
    fi
else
    echo "Done. No errors encountered." | tee -a "$LOG_FILE"
    [[ -f "$ERROR_LOG" ]] && rm -f "$ERROR_LOG"
fi
