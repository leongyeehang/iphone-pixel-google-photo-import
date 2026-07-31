#!/usr/bin/env bash
# group_files_size.sh: Group media into size-limited folders named by date range.
# Usage: ./group_files_size.sh [--dry-run] [--size SIZE] [input_directory]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" || { echo "Error: lib.sh not found next to $0" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: group_files_size.sh [--dry-run] [--size SIZE] [input_directory]

Group media files into size-limited folders named by date range (YYMMDD-YYMMDD-#.#GB).
Dates are parsed from renamed filenames (YYYYMMDD_HHMMSS) first, falling back to the
filesystem creation date. Non-media files are left in place. Runs on the current
directory if none is given.

Options:
  --size SIZE   Target folder size (default 15G; or set PHOTO_GROUP_SIZE). K/M/G suffixes.
  --dry-run     Preview folders that would be created; make no changes.
  -h, --help    Show this help and exit.
      --version Print version and exit.
EOF
}

DRY_RUN=false
INPUT_DIR=""
SIZE_INPUT="$PHOTO_GROUP_SIZE"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --size)
      SIZE_INPUT="${2:-}"
      [[ -z "$SIZE_INPUT" ]] && { echo "Error: --size requires a value" >&2; exit 1; }
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --version) echo "group_files_size.sh $WORKFLOW_VERSION"; exit 0 ;;
    *) INPUT_DIR="$1"; shift ;;
  esac
done

INPUT_DIR="${INPUT_DIR:-.}"

if ! GROUP_SIZE_LIMIT=$(parse_size "$SIZE_INPUT"); then
    echo "Error: invalid --size '$SIZE_INPUT' (use e.g. 15G, 500M, 2K, or a byte count)." >&2
    exit 1
fi
if (( GROUP_SIZE_LIMIT <= 0 )); then
    echo "Error: --size must be greater than zero (got '$SIZE_INPUT')." >&2
    exit 1
fi
limit_gb=$(awk -v b="$GROUP_SIZE_LIMIT" 'BEGIN { printf "%.1f", b / (1024^3) }')

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Directory '$INPUT_DIR' not found." >&2
    exit 1
fi

cd "$INPUT_DIR" || exit 1

files_list=$(mktemp) || exit 1
trap 'rm -f "$files_list"' EXIT

# Build a date-sorted list (oldest first) of MEDIA files only.
while IFS= read -r -d '' filepath; do
    filepath="${filepath#./}"
    is_media_file "$filepath" || continue
    epoch=$(epoch_from_filename_or_fs "$filepath")
    printf '%s\t%s\n' "$epoch" "$filepath"
done < <(find . -maxdepth 1 -type f ! -name ".*" -print0) | sort -n | cut -f2- > "$files_list"

if [[ ! -s "$files_list" ]]; then
    echo "No media files found to group in '$INPUT_DIR'."
    exit 0
fi

current_group_size=0
current_group_files=()
group_min_epoch=""
group_max_epoch=""
COUNTER=0
groups_created=0

process_group() {
    local min_date max_date total_size_gb folder_name file
    min_date=$(epoch_to_yymmdd "$group_min_epoch")
    max_date=$(epoch_to_yymmdd "$group_max_epoch")
    total_size_gb=$(awk -v bytes="$current_group_size" 'BEGIN {printf "%.1f", bytes / (1024^3)}')
    folder_name="${min_date}-${max_date}-${total_size_gb}GB"

    # Enforce the shared naming contract: a folder we create must match the
    # GROUP_FOLDER_GLOB that ungroup.sh uses to find it. Loud failure beats
    # silent drift between the two scripts.
    # shellcheck disable=SC2053  # RHS is an intentional glob pattern, not a literal
    if [[ "$folder_name" != $GROUP_FOLDER_GLOB ]]; then
        echo "Internal error: folder name '$folder_name' does not match GROUP_FOLDER_GLOB." >&2
        exit 1
    fi

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
    # Use arithmetic assignment (not ((groups_created++))): a post-increment whose
    # pre-value is 0 makes (( )) return exit status 1, which can abort the script
    # under `set -e` on some bash builds.
    groups_created=$((groups_created + 1))
    COUNTER=$((COUNTER + ${#current_group_files[@]}))
}

while IFS= read -r FILE; do
    [[ -z "$FILE" ]] && continue
    file_size=$(stat_size "$FILE")

    if (( file_size > GROUP_SIZE_LIMIT )); then
        size_gb=$(awk -v b="$file_size" 'BEGIN {printf "%.1f", b / (1024^3)}')
        echo "Warning: '$FILE' (${size_gb}GB) exceeds the ${limit_gb}GB group limit; it will form its own over-limit folder." >&2
    fi

    file_epoch=$(epoch_from_filename_or_fs "$FILE")

    if [[ -n "$group_min_epoch" ]] && (( current_group_size + file_size > GROUP_SIZE_LIMIT )); then
        process_group
        current_group_size=0
        current_group_files=()
        group_min_epoch=""
        group_max_epoch=""
    fi

    current_group_files+=("$FILE")
    current_group_size=$((current_group_size + file_size))

    if [[ -z "$group_min_epoch" ]] || (( file_epoch < group_min_epoch )); then group_min_epoch=$file_epoch; fi
    if [[ -z "$group_max_epoch" ]] || (( file_epoch > group_max_epoch )); then group_max_epoch=$file_epoch; fi
done < "$files_list"

if [[ ${#current_group_files[@]} -gt 0 ]]; then process_group; fi

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run complete. Would group $COUNTER files into $groups_created folder(s)."
else
    echo "Done. Grouped $COUNTER files into $groups_created folder(s)."
fi
