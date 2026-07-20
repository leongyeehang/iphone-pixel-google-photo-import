#!/usr/bin/env bash

# ungroup.sh: Move all files from grouped subfolders back to the parent directory.
# Usage: ./ungroup.sh [input_directory]
# This reverses the grouping step so you can re-group with different settings.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ungroup.sh [input_directory]

Reverse the grouping step: move all files from YYMMDD-YYMMDD-#.#GB/ subfolders back to
the parent directory and remove the emptied folders. Runs on the current directory if no
input directory is given. No files are deleted; name collisions are skipped with a warning.

Options:
  -h, --help    Show this help and exit.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

INPUT_DIR="${1:-.}"

if [[ ! -d "$INPUT_DIR" ]]; then
    echo "Error: Directory '$INPUT_DIR' not found." >&2
    exit 1
fi

cd "$INPUT_DIR" || exit 1

# Find grouped subfolders (pattern: YYMMDD-YYMMDD-*GB)
moved=0
folders_removed=0

for folder in [0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-*GB; do
    [[ -d "$folder" ]] || continue

    echo "Ungrouping: $folder/"
    for file in "$folder"/*; do
        [[ -f "$file" ]] || continue
        basename=$(basename "$file")

        if [[ -e "$basename" ]]; then
            echo "Warning: '$basename' already exists in parent, skipping." >&2
            continue
        fi

        mv "$file" .
        moved=$((moved + 1))
    done

    # Remove folder only if empty
    if rmdir "$folder" 2>/dev/null; then
        folders_removed=$((folders_removed + 1))
    else
        echo "Warning: '$folder/' not empty after ungrouping, kept in place." >&2
    fi
done

if [[ $moved -eq 0 ]]; then
    echo "No grouped folders found to undo."
else
    echo "Done. Moved $moved files back, removed $folders_removed empty folder(s)."
fi
