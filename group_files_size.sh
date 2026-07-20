#!/usr/bin/env bash

# group_files_size.sh: Group files into ~15GB folders named by date range
# Usage: ./group_files_size.sh [--dry-run] [input_directory]
# Dates are parsed from renamed filenames (YYYYMMDD_HHMMSS.ext) first,
# falling back to filesystem creation date.

set -euo pipefail

# Defaults
DRY_RUN=false
INPUT_DIR=""

# Parse arguments
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      INPUT_DIR="$1"
      shift
      ;;
  esac
done

INPUT_DIR="${INPUT_DIR:-.}"

# Check if the input directory exists
if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Directory '$INPUT_DIR' not found." >&2
    exit 1
fi

cd "$INPUT_DIR" || exit 1

# Temp file cleanup on exit
files_list=$(mktemp) || exit 1
trap 'rm -f "$files_list"' EXIT

# get_file_epoch: Extract epoch from filename (YYYYMMDD_HHMMSS pattern) or fall back to filesystem date
# Usage: get_file_epoch <filepath>
get_file_epoch() {
    local filepath="$1"
    local basename
    basename=$(basename "$filepath")

    # Try to parse YYYYMMDD_HHMMSS from the filename
    if [[ "$basename" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
        local year="${BASH_REMATCH[1]}"
        local month="${BASH_REMATCH[2]}"
        local day="${BASH_REMATCH[3]}"
        local hour="${BASH_REMATCH[4]}"
        local min="${BASH_REMATCH[5]}"
        local sec="${BASH_REMATCH[6]}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            date -j -f "%Y%m%d%H%M%S" "${year}${month}${day}${hour}${min}${sec}" +"%s" 2>/dev/null && return
        else
            date -d "${year}-${month}-${day} ${hour}:${min}:${sec}" +"%s" 2>/dev/null && return
        fi
    fi

    # Fallback: filesystem creation date
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f "%B" "$filepath"
    else
        local ctime
        ctime=$(stat -c "%W" "$filepath")
        if [[ "$ctime" == "0" ]]; then
            stat -c "%Y" "$filepath"
        else
            echo "$ctime"
        fi
    fi
}

# Build sorted file list by date (oldest first), exclude scripts and logs
# Use tab as delimiter to handle filenames with spaces
while IFS= read -r -d '' filepath; do
    filepath="${filepath#./}"  # Strip leading ./
    epoch=$(get_file_epoch "$filepath")
    printf '%s\t%s\n' "$epoch" "$filepath"
done < <(find . -maxdepth 1 -type f ! -name "*.sh" ! -name "*.py" ! -name "*.log" ! -name ".*" -print0) | sort -n | cut -f2- > "$files_list"

# Check if any files were found
if [[ ! -s "$files_list" ]]; then
    echo "No files found to group in '$INPUT_DIR'."
    exit 0
fi

# Grouping parameters
GROUP_SIZE_LIMIT=$((15 * 1024 * 1024 * 1024))  # 15GB in bytes
current_group_size=0
current_group_files=()
group_min_epoch=""
group_max_epoch=""
COUNTER=0
groups_created=0

process_group() {
    # Convert epochs to dates (YYMMDD format)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        min_date=$(date -j -f "%s" "$group_min_epoch" +"%y%m%d")
        max_date=$(date -j -f "%s" "$group_max_epoch" +"%y%m%d")
    else
        min_date=$(date -d "@$group_min_epoch" +"%y%m%d")
        max_date=$(date -d "@$group_max_epoch" +"%y%m%d")
    fi

    # Calculate total size in GB with 1 decimal place
    total_size_gb=$(awk -v bytes="$current_group_size" 'BEGIN {printf "%.1f", bytes / (1024^3)}')

    folder_name="${min_date}-${max_date}-${total_size_gb}GB"

    if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would create folder: $folder_name (${#current_group_files[@]} files, ${total_size_gb}GB)"
    else
        mkdir -p "$folder_name"
        for file in "${current_group_files[@]}"; do
            if ! mv "$file" "$folder_name/"; then
                echo "Error: Failed to move '$file' to '$folder_name/'" >&2
                exit 1
            fi
        done
    fi
    ((groups_created++))
    COUNTER=$((COUNTER + ${#current_group_files[@]}))
}

while IFS= read -r FILE; do
    [[ -z "$FILE" ]] && continue

    # Get file size
    if [[ "$OSTYPE" == "darwin"* ]]; then
        file_size=$(stat -f "%z" "$FILE")
    else
        file_size=$(stat -c "%s" "$FILE")
    fi

    # Get file epoch using the fallback chain
    file_epoch=$(get_file_epoch "$FILE")

    # Start new group if adding this file would exceed the limit
    if [[ -n "$group_min_epoch" ]] && (( current_group_size + file_size > GROUP_SIZE_LIMIT )); then
        process_group
        current_group_size=0
        current_group_files=()
        group_min_epoch=""
        group_max_epoch=""
    fi

    # Update group metadata
    current_group_files+=("$FILE")
    current_group_size=$((current_group_size + file_size))

    # Update date boundaries
    if [[ -z "$group_min_epoch" ]] || (( file_epoch < group_min_epoch )); then
        group_min_epoch=$file_epoch
    fi
    if [[ -z "$group_max_epoch" ]] || (( file_epoch > group_max_epoch )); then
        group_max_epoch=$file_epoch
    fi
done < "$files_list"

# Process remaining files
if [[ ${#current_group_files[@]} -gt 0 ]]; then
    process_group
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run complete. Would group $COUNTER files into $groups_created folder(s)."
else
    echo "Done. Grouped $COUNTER files into $groups_created folder(s)."
fi
