#!/usr/bin/env bash

# run_mux_motionphoto.sh: Convert iPhone Live Photos to Google Motion Photos
# Usage: ./run_mux_motionphoto.sh <input_directory>

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: run_mux_motionphoto.sh <input_directory>

Convert iPhone Live Photos (JPG/HEIC + companion MOV) into Google Motion Photos using the
installed `motionphoto2` binary. Output is written to <input_directory>/muxed-photo/;
original files are not modified. Non-Live-Photo files are copied as-is.

Options:
  -h, --help    Show this help and exit.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Check for the existence of the `motionphoto2` binary.
if ! command -v motionphoto2 &> /dev/null; then
    echo "Error: 'motionphoto2' not found. Please install from https://github.com/PetrVys/MotionPhoto2" >&2
    exit 1
fi

# Require input directory as argument
if [[ -z "${1:-}" ]]; then
    echo "Usage: $0 <input_directory>" >&2
    exit 1
fi

INPUT_DIR="$1"

# Check if the input directory exists.
if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Input directory '$INPUT_DIR' not found." >&2
    exit 1
fi

# Define the output directory and error log.
OUTPUT_DIR="$INPUT_DIR/muxed-photo"
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
