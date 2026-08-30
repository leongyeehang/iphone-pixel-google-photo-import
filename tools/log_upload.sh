#!/usr/bin/env bash

# log_upload.sh: Record a transferred Batch in upload-log.md once Google Photos
# has confirmed the backup.
# Usage: ./tools/log_upload.sh [options] <batch_directory> [notes]
#
# The upload log answers the question the toolkit cannot: what has Google actually
# confirmed holding? library-ledger.tsv records what was PRODUCED on the Mac; this
# records what was CONFIRMED uploaded. Never delete a local copy until the batch
# appears here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib.sh
. "$SCRIPT_DIR/../lib.sh" || { echo "Error: lib.sh not found above $0" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: log_upload.sh [options] <batch_directory> [notes...]

Append a row to upload-log.md recording that a Batch has been confirmed backed up
to Google Photos. The Batch name, its import folder and its file count are read from
the directory; the dates default to today.

By default the log is found by walking up from <batch_directory> looking for an
existing upload-log.md (override with --log or PHOTO_UPLOAD_LOG). The file is created
with a header row if it does not exist.

Options:
  --log PATH        Path to the upload log (default: PHOTO_UPLOAD_LOG, else the
                    nearest upload-log.md above the batch directory).
  --pushed DATE     Date the batch was copied to the device (default: today).
  --confirmed DATE  Date Google Photos confirmed the backup (default: today).
  -h, --help        Show this help and exit.
      --version     Print version and exit.

Example:
  ./tools/log_upload.sh ~/lib/2026July28/muxed-photo/260415-260503-9.8GB "motion verified"
EOF
}

TODAY="$(date +%F)"
LOG_PATH="${PHOTO_UPLOAD_LOG:-}"
PUSHED=""
CONFIRMED=""
BATCH_DIR=""
NOTES=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --version) echo "log_upload.sh $WORKFLOW_VERSION"; exit 0 ;;
        --log)
            LOG_PATH="${2:-}"
            [[ -z "$LOG_PATH" ]] && { echo "Error: --log requires a path" >&2; exit 1; }
            shift 2 ;;
        --pushed)
            PUSHED="${2:-}"
            [[ -z "$PUSHED" ]] && { echo "Error: --pushed requires a date" >&2; exit 1; }
            shift 2 ;;
        --confirmed)
            CONFIRMED="${2:-}"
            [[ -z "$CONFIRMED" ]] && { echo "Error: --confirmed requires a date" >&2; exit 1; }
            shift 2 ;;
        *)
            if [[ -z "$BATCH_DIR" ]]; then BATCH_DIR="$1"
            elif [[ -z "$NOTES" ]]; then NOTES="$1"
            else NOTES="$NOTES $1"
            fi
            shift ;;
    esac
done

if [[ -z "$BATCH_DIR" ]]; then
    echo "Usage: $0 [options] <batch_directory> [notes...]" >&2
    exit 1
fi
if [[ ! -d "$BATCH_DIR" ]]; then
    echo "Error: Batch directory '$BATCH_DIR' not found." >&2
    exit 1
fi

PUSHED="${PUSHED:-$TODAY}"
CONFIRMED="${CONFIRMED:-$TODAY}"

BATCH_DIR="$(cd "$BATCH_DIR" && pwd)"
BATCH="$(basename "$BATCH_DIR")"

# A Batch is a grouped folder; warn (don't fail) if it isn't one, so an
# ungrouped or renamed folder can still be recorded deliberately.
# shellcheck disable=SC2053  # RHS is an intentional glob pattern, not a literal
if [[ "$BATCH" != $GROUP_FOLDER_GLOB ]]; then
    echo "Warning: '$BATCH' does not look like a Batch folder (YYMMDD-YYMMDD-#.#GB)." >&2
fi

# <import>/muxed-photo/<batch>  ->  the import folder is two levels up.
IMPORT="$(basename "$(dirname "$(dirname "$BATCH_DIR")")")"
FILES="$(find "$BATCH_DIR" -type f ! -name '.*' | wc -l | tr -d ' ')"

# Locate the log: explicit path, else the nearest existing upload-log.md above the batch.
if [[ -z "$LOG_PATH" ]]; then
    probe="$BATCH_DIR"
    for _ in 1 2 3 4 5 6; do
        probe="$(dirname "$probe")"
        [[ "$probe" == "/" ]] && break
        if [[ -f "$probe/upload-log.md" ]]; then LOG_PATH="$probe/upload-log.md"; break; fi
    done
fi
if [[ -z "$LOG_PATH" ]]; then
    echo "Error: no upload-log.md found above '$BATCH_DIR'." >&2
    echo "Pass --log PATH or set PHOTO_UPLOAD_LOG to say where it should live." >&2
    exit 1
fi

if [[ ! -f "$LOG_PATH" ]]; then
    printf '| Batch | Import | Files | Pushed | Backup confirmed | Notes |\n|---|---|---|---|---|---|\n' > "$LOG_PATH"
    echo "Created $LOG_PATH"
fi

if grep -qF "| $BATCH |" "$LOG_PATH"; then
    echo "Warning: '$BATCH' is already recorded in $LOG_PATH. Appending anyway." >&2
fi

printf '| %s | %s | %s | %s | %s | %s |\n' \
    "$BATCH" "$IMPORT" "$FILES" "$PUSHED" "$CONFIRMED" "$NOTES" >> "$LOG_PATH"

echo "Recorded in $LOG_PATH:"
tail -n 1 "$LOG_PATH"
