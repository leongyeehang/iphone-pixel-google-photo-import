#!/usr/bin/env bash

# masterscript.sh: Automate the photo workflow (mux → rename → group)
# Usage: ./masterscript.sh [target_directory]
# Supports resume: re-run to skip already-completed steps.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: masterscript.sh [target_directory]

Automate the photo workflow: mux Live Photos -> rename by timestamp -> group by size.
Runs on the current directory if no target is given. Supports resume: re-run to skip
already-completed steps (checkpoints are kept in <target>/.workflow/).

Options:
  -h, --help    Show this help and exit.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

# Resolve the directory where this script lives (for calling sibling scripts)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check for a command-line argument; use it as the input directory if provided.
INPUT_DIR="${1:-.}"

# Check the directory exists BEFORE resolving it. Resolving with `cd` on a missing
# directory would abort under `set -e` with a raw error, bypassing the friendly
# message below.
if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Directory '$INPUT_DIR' not found." >&2
    exit 1
fi

# Resolve to absolute path
INPUT_DIR="$(cd "$INPUT_DIR" && pwd)"

# Define the output directory for converted photos.
MUXED_DIR="$INPUT_DIR/muxed-photo"

# Logs and checkpoints go in a hidden subdirectory to avoid being copied by motionphoto2
WORK_DIR="$INPUT_DIR/.workflow"
mkdir -p "$WORK_DIR"

CHECKPOINT_MUX="$WORK_DIR/.mux_done"
CHECKPOINT_RENAME="$WORK_DIR/.rename_done"
CHECKPOINT_GROUP="$WORK_DIR/.group_done"
LOG_FILE="$WORK_DIR/workflow.log"

log() {
    local msg
    msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$msg" | tee -a "$LOG_FILE"
}

# Disk space pre-flight check.
# Use -k (1024-byte blocks) and -P (POSIX single-line output) for portable, consistent
# sizing across macOS and Linux. On a resume run `du` also counts the existing
# muxed-photo/ copy, which only over-estimates the requirement — a safe direction for a
# "you may need ~2x" warning.
input_size_kb=$(du -sk "$INPUT_DIR" | awk '{print $1}')
input_size_gb=$(awk -v kb="$input_size_kb" 'BEGIN {printf "%.1f", kb / (1024*1024)}')
free_space_kb=$(df -Pk "$INPUT_DIR" | awk 'NR==2 {print $4}')
free_space_gb=$(awk -v kb="$free_space_kb" 'BEGIN {printf "%.1f", kb / (1024*1024)}')
required_gb=$(awk -v sz="$input_size_gb" 'BEGIN {printf "%.1f", sz * 2}')

log "Starting photo workflow in: $INPUT_DIR"
log "Input size: ${input_size_gb}GB | Free space: ${free_space_gb}GB | Estimated need: ${required_gb}GB"

if (( $(awk -v free="$free_space_gb" -v need="$required_gb" 'BEGIN {print (free < need) ? 1 : 0}') )); then
    log "WARNING: Free disk space (${free_space_gb}GB) may not be enough. Need ~${required_gb}GB (2x input). Continue at your own risk."
fi

# Step 1: Mux Live Photos (before rename to preserve original filenames for matching)
if [[ -f "$CHECKPOINT_MUX" ]]; then
    log "--- Step 1: Skipping muxing (already completed) ---"
else
    log "--- Step 1: Converting Live Photos ---"
    "$SCRIPT_DIR/run_mux_motionphoto.sh" "$INPUT_DIR" 2>&1 | tee -a "$LOG_FILE"
    touch "$CHECKPOINT_MUX"
    log "--- Step 1: Complete ---"
fi

# Validate muxed directory exists before proceeding
if [[ ! -d "$MUXED_DIR" ]]; then
    log "Error: '$MUXED_DIR' was not created by Step 1. Cannot proceed." >&2
    exit 1
fi

# Step 2: Rename the files in muxed-photo (originals in input dir stay untouched)
if [[ -f "$CHECKPOINT_RENAME" ]]; then
    log "--- Step 2: Skipping rename (already completed) ---"
else
    log "--- Step 2: Renaming media files ---"
    "$SCRIPT_DIR/rename_media.sh" "$MUXED_DIR" 2>&1 | tee -a "$LOG_FILE"
    touch "$CHECKPOINT_RENAME"
    log "--- Step 2: Complete ---"
fi

# Step 3: Group the files into folders
if [[ -f "$CHECKPOINT_GROUP" ]]; then
    log "--- Step 3: Skipping grouping (already completed) ---"
else
    log "--- Step 3: Grouping files by size ---"
    "$SCRIPT_DIR/group_files_size.sh" "$MUXED_DIR" 2>&1 | tee -a "$LOG_FILE"
    touch "$CHECKPOINT_GROUP"
    log "--- Step 3: Complete ---"
fi

# Clean up checkpoint files on success
rm -f "$CHECKPOINT_MUX" "$CHECKPOINT_RENAME" "$CHECKPOINT_GROUP"

log "--- Workflow complete ---"
log "Results are in: $MUXED_DIR"
log "Full log: $LOG_FILE"

# Move the workflow log to the output directory for reference, then clean up
cp "$LOG_FILE" "$MUXED_DIR/workflow.log" 2>/dev/null || true
rm -rf "$WORK_DIR"
# rename_media.sh writes its own logs into muxed-photo/.workflow/ (that dir is its
# target). The consolidated workflow.log already captured that output via tee, so
# remove the leftover hidden dir too.
rm -rf "$MUXED_DIR/.workflow"
