#!/usr/bin/env bash

# run_mux_motionphoto.sh: Convert iPhone Live Photos to Google Motion Photos
# Usage: ./run_mux_motionphoto.sh [--output-name NAME] <input_directory>

set -euo pipefail

VERSION="1.0.0"

usage() {
    cat <<'EOF'
Usage: run_mux_motionphoto.sh [--output-name NAME] <input_directory>

Convert iPhone Live Photos (JPG/HEIC + companion MOV) into Google Motion Photos using the
installed `motionphoto2` binary. Output is written to <input_directory>/<output-name>/
(default: muxed-photo); original files are not modified. Non-Live-Photo files are copied
as-is.

Options:
  --output-name NAME   Name of the output subfolder (default: muxed-photo).
  -h, --help           Show this help and exit.
      --version        Print version and exit.
EOF
}

OUTPUT_NAME="muxed-photo"
INPUT_DIR=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --version)
      echo "run_mux_motionphoto.sh $VERSION"
      exit 0
      ;;
    --output-name)
      OUTPUT_NAME="${2:-}"
      [[ -z "$OUTPUT_NAME" ]] && { echo "Error: --output-name requires a value" >&2; exit 1; }
      shift 2
      ;;
    *)
      INPUT_DIR="$1"
      shift
      ;;
  esac
done

# Check for the existence of the `motionphoto2` binary.
if ! command -v motionphoto2 &> /dev/null; then
    echo "Error: 'motionphoto2' not found. Please install from https://github.com/PetrVys/MotionPhoto2" >&2
    exit 1
fi

# Require input directory
if [[ -z "$INPUT_DIR" ]]; then
    echo "Usage: $0 [--output-name NAME] <input_directory>" >&2
    exit 1
fi

# Check if the input directory exists.
if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Input directory '$INPUT_DIR' not found." >&2
    exit 1
fi

# Define the output directory and error log.
OUTPUT_DIR="$INPUT_DIR/$OUTPUT_NAME"
ERROR_LOG="$OUTPUT_DIR/muxing_errors.log"

# Create the output directory if it doesn't exist.
mkdir -p "$OUTPUT_DIR"
echo "Output directory: $OUTPUT_DIR"

# Run the motionphoto2 command with the specified options.
echo "Starting Live Photo muxing process..."
if motionphoto2 \
    --input-directory "$INPUT_DIR" \
    --output-directory "$OUTPUT_DIR" \
    --exif-match \
    --copy-unmuxed \
    2> "$ERROR_LOG"; then
    echo "Muxing process finished successfully. Check '$OUTPUT_DIR' for results."
    # Remove empty error log
    if [[ ! -s "$ERROR_LOG" ]]; then
        rm -f "$ERROR_LOG"
    fi
else
    echo "Warning: motionphoto2 exited with errors. Check '$ERROR_LOG' for details." >&2
    echo "Output files may still be usable in '$OUTPUT_DIR'."
fi
