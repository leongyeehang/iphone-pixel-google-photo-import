#!/usr/bin/env bash
# run_mux_motionphoto.sh: Convert iPhone Live Photos to Google Motion Photos.
# Usage: ./run_mux_motionphoto.sh [--output-name NAME] <input_directory>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" || { echo "Error: lib.sh not found next to $0" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: run_mux_motionphoto.sh [--output-name NAME] <input_directory>

Convert iPhone Live Photos (JPG/HEIC + companion MOV) into Google Motion Photos using the
installed `motionphoto2` binary. Output goes to <input_directory>/<output-name>/
(default: muxed-photo, or PHOTO_OUTPUT_NAME); originals are not modified. Non-Live-Photo
files are copied as-is. If motionphoto2 is not installed, muxing is skipped with a warning.

Options:
  --output-name NAME   Output subfolder name (default muxed-photo; or PHOTO_OUTPUT_NAME).
  -h, --help           Show this help and exit.
      --version        Print version and exit.
EOF
}

OUTPUT_NAME="$PHOTO_OUTPUT_NAME"
INPUT_DIR=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --version) echo "run_mux_motionphoto.sh $WORKFLOW_VERSION"; exit 0 ;;
    --output-name)
      OUTPUT_NAME="${2:-}"
      [[ -z "$OUTPUT_NAME" ]] && { echo "Error: --output-name requires a value" >&2; exit 1; }
      shift 2 ;;
    *) INPUT_DIR="$1"; shift ;;
  esac
done

# Missing binary is a graceful skip (exit 0), NOT a hard error — non-iPhone users can
# still run the wider pipeline.
if ! command -v motionphoto2 &> /dev/null; then
    echo "Note: 'motionphoto2' not found — skipping Live-Photo muxing." >&2
    echo "(Install from https://github.com/PetrVys/MotionPhoto2 to enable it.)" >&2
    exit 0
fi

if [[ -z "$INPUT_DIR" ]]; then
    echo "Usage: $0 [--output-name NAME] <input_directory>" >&2
    exit 1
fi
if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Input directory '$INPUT_DIR' not found." >&2
    exit 1
fi

OUTPUT_DIR="$INPUT_DIR/$OUTPUT_NAME"
ERROR_LOG="$OUTPUT_DIR/muxing_errors.log"

mkdir -p "$OUTPUT_DIR"
echo "Output directory: $OUTPUT_DIR"
echo "Starting Live Photo muxing process..."
if motionphoto2 \
    --input-directory "$INPUT_DIR" \
    --output-directory "$OUTPUT_DIR" \
    --exif-match \
    --copy-unmuxed \
    2> "$ERROR_LOG"; then
    echo "Muxing process finished successfully. Check '$OUTPUT_DIR' for results."
    [[ ! -s "$ERROR_LOG" ]] && rm -f "$ERROR_LOG"
else
    echo "Warning: motionphoto2 exited with errors. Check '$ERROR_LOG' for details." >&2
    echo "Output files may still be usable in '$OUTPUT_DIR'."
fi
