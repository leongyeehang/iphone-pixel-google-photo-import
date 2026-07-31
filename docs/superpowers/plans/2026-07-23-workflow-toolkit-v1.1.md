# Photo Workflow Toolkit v1.1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Generalize the photo toolkit into a universal, configurable tool while keeping every shipped default identical to the current iPhone→Pixel behavior.

**Architecture:** Introduce a sourced `lib.sh` that centralizes the version, the overridable `PHOTO_*` defaults (via `: "${VAR:=default}"`), the media-extension identity functions, and the portable `date`/`stat`/size helpers. Every script sources it and reads the shared values, so rename and group can no longer disagree on file types. `masterscript.sh` gains graceful mux-skip, copy-by-default (with `--in-place` opt-out), a disk-space resume fix, and an end-of-run summary + ledger.

**Tech Stack:** Bash (POSIX-ish, bash 3.2-compatible), `exiftool`, `motionphoto2` (optional), `bats-core` for tests, `shellcheck` for lint.

## Global Constraints

- **Bash 3.2 compatible** (macOS default): no `mapfile`/`readarray`, no `${var,,}` — use `tr` for case-folding, `while read` loops for arrays.
- **`shellcheck *.sh` must stay clean.** For dynamic sourcing use `# shellcheck source=lib.sh`; in `lib.sh` add `# shellcheck disable=SC2034` for values consumed by sourcing scripts.
- **Portable macOS + Linux:** keep the `[[ "$OSTYPE" == "darwin"* ]]` branches for `stat`/`date`.
- **No new runtime dependencies.** No config-file parser, no non-coreutils tools.
- **Defaults unchanged.** Shipped defaults reproduce v1.0 output for the author's flow.
- **Version:** all scripts print `1.1.0` via the shared `WORKFLOW_VERSION`.
- **Exact default values (copy verbatim):**
  - `PHOTO_GROUP_SIZE=15G`, `PHOTO_OUTPUT_NAME=muxed-photo`
  - `PHOTO_IMAGE_EXTS=jpg jpeg heic heif dng png tif tiff gif bmp webp`
  - `PHOTO_VIDEO_EXTS=mov mp4 m4v avi 3gp 3g2 mts m2ts mkv wmv`
  - `PHOTO_DATE_TAGS=FileModifyDate FileCreateDate DateTimeCreated XMP:CreateDate CreateDate DateTimeOriginal`
  - `PHOTO_VIDEO_DATE_TAGS=FileModifyDate FileCreateDate TrackCreateDate MediaCreateDate QuickTime:CreateDate`
  - Rename date format string: `%Y%m%d_%H%M%S%%-c.%%e`
  - Grouped-folder glob: `[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-*GB`
  - Ledger columns (TSV, fixed): `run_completed_at import_dir target_dir date_from date_to images videos motion_photos total_files total_size_gb batches`

---

### Task 1: `lib.sh` — version, overridable defaults, media identity

**Files:**
- Create: `lib.sh`
- Test: `test/test_lib.bats`

**Interfaces:**
- Produces (consumed by all later tasks):
  - `WORKFLOW_VERSION` (string `1.1.0`)
  - env-backed vars: `PHOTO_GROUP_SIZE`, `PHOTO_OUTPUT_NAME`, `PHOTO_IMAGE_EXTS`, `PHOTO_VIDEO_EXTS`, `PHOTO_DATE_TAGS`, `PHOTO_VIDEO_DATE_TAGS`, `PHOTO_LEDGER`
  - `GROUP_FOLDER_GLOB` (string)
  - `is_image_file <path>` → exit 0/1; `is_video_file <path>` → exit 0/1; `is_media_file <path>` → exit 0/1

- [ ] **Step 1: Write the failing test**

Create `test/test_lib.bats`:

```bash
#!/usr/bin/env bats
#
# Unit tests for lib.sh: media identity + (Task 2) portable helpers.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=/dev/null
  source "$DIR/lib.sh"
}

@test "WORKFLOW_VERSION is set" {
  [ "$WORKFLOW_VERSION" = "1.1.0" ]
}

@test "is_media_file accepts images/videos (any case), rejects non-media" {
  run is_media_file "photo.JPG"; [ "$status" -eq 0 ]
  run is_media_file "shot.PNG";  [ "$status" -eq 0 ]
  run is_media_file "clip.mp4";  [ "$status" -eq 0 ]
  run is_media_file "movie.MTS"; [ "$status" -eq 0 ]
  run is_media_file "notes.txt"; [ "$status" -ne 0 ]
  run is_media_file "run.sh";    [ "$status" -ne 0 ]
  run is_media_file ".DS_Store"; [ "$status" -ne 0 ]
}

@test "is_image_file / is_video_file classify correctly" {
  run is_image_file "a.heic"; [ "$status" -eq 0 ]
  run is_image_file "a.mov";  [ "$status" -ne 0 ]
  run is_video_file "a.mov";  [ "$status" -eq 0 ]
  run is_video_file "a.jpg";  [ "$status" -ne 0 ]
}

@test "PHOTO_IMAGE_EXTS override narrows what counts as media" {
  PHOTO_IMAGE_EXTS="jpg"
  run is_media_file "shot.png"; [ "$status" -ne 0 ]
  run is_media_file "pic.jpg";  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats test/test_lib.bats`
Expected: FAIL — `lib.sh` does not exist / functions undefined.

- [ ] **Step 3: Write minimal implementation**

Create `lib.sh`:

```bash
#!/usr/bin/env bash
# lib.sh: shared config, media-type identity, and portable helpers for the
# photo-workflow toolkit. Sourced by every script. Defaults reproduce the
# author's iPhone->Pixel behavior; override any PHOTO_* var via env or a flag.
#
# shellcheck disable=SC2034  # vars/globs below are consumed by sourcing scripts

# Single version for all scripts.
WORKFLOW_VERSION="1.1.0"

# --- Overridable defaults (env wins over these; a flag wins over env) ---------
: "${PHOTO_GROUP_SIZE:=15G}"
: "${PHOTO_OUTPUT_NAME:=muxed-photo}"
: "${PHOTO_IMAGE_EXTS:=jpg jpeg heic heif dng png tif tiff gif bmp webp}"
: "${PHOTO_VIDEO_EXTS:=mov mp4 m4v avi 3gp 3g2 mts m2ts mkv wmv}"
# EXIF date-tag fallback chains, lowest-priority FIRST (exiftool: last match wins).
: "${PHOTO_DATE_TAGS:=FileModifyDate FileCreateDate DateTimeCreated XMP:CreateDate CreateDate DateTimeOriginal}"
: "${PHOTO_VIDEO_DATE_TAGS:=FileModifyDate FileCreateDate TrackCreateDate MediaCreateDate QuickTime:CreateDate}"
# Empty => masterscript picks a target-relative default.
: "${PHOTO_LEDGER:=}"

# Grouped-folder name pattern: group_files_size.sh CREATES it, ungroup.sh GLOBS
# it. A shared constant, deliberately NOT user-configurable.
GROUP_FOLDER_GLOB='[0-9][0-9][0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9][0-9][0-9]-*GB'

# --- Media-type identity ------------------------------------------------------
_ext_lc() { printf '%s' "${1##*.}" | tr '[:upper:]' '[:lower:]'; }

is_image_file() {
    local x e; x="$(_ext_lc "$1")"
    for e in $PHOTO_IMAGE_EXTS; do [[ "$x" == "$e" ]] && return 0; done
    return 1
}
is_video_file() {
    local x e; x="$(_ext_lc "$1")"
    for e in $PHOTO_VIDEO_EXTS; do [[ "$x" == "$e" ]] && return 0; done
    return 1
}
is_media_file() { is_image_file "$1" || is_video_file "$1"; }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats test/test_lib.bats`
Expected: PASS (4 tests).

- [ ] **Step 5: Lint**

Run: `shellcheck lib.sh`
Expected: no output (clean).

- [ ] **Step 6: Commit**

```bash
git add lib.sh test/test_lib.bats
git commit -m "feat(lib): add lib.sh with version, PHOTO_* defaults, media identity"
```

---

### Task 2: `lib.sh` — portable helpers + `parse_size`

**Files:**
- Modify: `lib.sh` (append helper functions)
- Test: `test/test_lib.bats` (add cases)

**Interfaces:**
- Produces: `stat_size <file>`→bytes; `stat_ctime <file>`→epoch; `epoch_from_filename_or_fs <file>`→epoch; `epoch_to_yymmdd <epoch>`→`YYMMDD`; `epoch_to_ymd <epoch>`→`YYYY-MM-DD`; `dir_size_kb <dir>`→KB (0 if missing); `parse_size <human>`→bytes on stdout, non-zero exit on invalid.

- [ ] **Step 1: Write the failing test**

Append to `test/test_lib.bats`:

```bash
@test "parse_size handles K/M/G suffixes and rejects bad input" {
  run parse_size "15G";  [ "$status" -eq 0 ]; [ "$output" = "16106127360" ]
  run parse_size "500M"; [ "$status" -eq 0 ]; [ "$output" = "524288000" ]
  run parse_size "2K";   [ "$status" -eq 0 ]; [ "$output" = "2048" ]
  run parse_size "1024"; [ "$status" -eq 0 ]; [ "$output" = "1024" ]
  run parse_size "bogus";[ "$status" -ne 0 ]
}

@test "epoch_from_filename_or_fs parses YYYYMMDD_HHMMSS" {
  run epoch_from_filename_or_fs "20250101_120000.JPG"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "stat_size and dir_size_kb work on real files" {
  tmp="$(mktemp -d)"
  printf 'abcde' > "$tmp/f.jpg"
  run stat_size "$tmp/f.jpg"; [ "$status" -eq 0 ]; [ "$output" = "5" ]
  run dir_size_kb "$tmp";     [ "$status" -eq 0 ]; [[ "$output" =~ ^[0-9]+$ ]]
  run dir_size_kb "$tmp/nope";[ "$status" -eq 0 ]; [ "$output" = "0" ]
  rm -rf "$tmp"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats test/test_lib.bats`
Expected: FAIL — `parse_size`/`stat_size`/etc. undefined.

- [ ] **Step 3: Write minimal implementation**

Append to `lib.sh`:

```bash
# --- Portable filesystem / date / size helpers --------------------------------
stat_size() {
    if [[ "$OSTYPE" == "darwin"* ]]; then stat -f "%z" "$1"; else stat -c "%s" "$1"; fi
}

stat_ctime() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        stat -f "%B" "$1"
    else
        local ctime; ctime=$(stat -c "%W" "$1")
        if [[ "$ctime" == "0" ]]; then stat -c "%Y" "$1"; else echo "$ctime"; fi
    fi
}

epoch_from_filename_or_fs() {
    local base; base=$(basename "$1")
    if [[ "$base" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})_([0-9]{2})([0-9]{2})([0-9]{2}) ]]; then
        local y="${BASH_REMATCH[1]}" mo="${BASH_REMATCH[2]}" d="${BASH_REMATCH[3]}"
        local h="${BASH_REMATCH[4]}" mi="${BASH_REMATCH[5]}" s="${BASH_REMATCH[6]}"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            date -j -f "%Y%m%d%H%M%S" "${y}${mo}${d}${h}${mi}${s}" +"%s" 2>/dev/null && return
        else
            date -d "${y}-${mo}-${d} ${h}:${mi}:${s}" +"%s" 2>/dev/null && return
        fi
    fi
    stat_ctime "$1"
}

epoch_to_yymmdd() {
    if [[ "$OSTYPE" == "darwin"* ]]; then date -j -f "%s" "$1" +"%y%m%d"; else date -d "@$1" +"%y%m%d"; fi
}
epoch_to_ymd() {
    if [[ "$OSTYPE" == "darwin"* ]]; then date -j -f "%s" "$1" +"%Y-%m-%d"; else date -d "@$1" +"%Y-%m-%d"; fi
}

dir_size_kb() {
    [[ -d "$1" ]] || { echo 0; return 0; }
    du -sk "$1" | awk '{print $1}'
}

parse_size() {
    local input="$1"
    if [[ "$input" =~ ^([0-9]+(\.[0-9]+)?)([KkMmGg]?)[Bb]?$ ]]; then
        local num="${BASH_REMATCH[1]}" unit="${BASH_REMATCH[3]}" mult=1
        case "$unit" in
            K|k) mult=1024 ;;
            M|m) mult=$((1024 * 1024)) ;;
            G|g) mult=$((1024 * 1024 * 1024)) ;;
        esac
        awk -v n="$num" -v m="$mult" 'BEGIN { printf "%d", n * m }'
        return 0
    fi
    return 1
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bats test/test_lib.bats`
Expected: PASS (all Task 1 + Task 2 cases).

- [ ] **Step 5: Lint & commit**

```bash
shellcheck lib.sh
git add lib.sh test/test_lib.bats
git commit -m "feat(lib): add portable stat/date/size helpers and parse_size"
```

---

### Task 3: Rewire `group_files_size.sh` onto `lib.sh`

**Files:**
- Modify: `group_files_size.sh` (source lib; use `is_media_file`, lib helpers, `GROUP_FOLDER_GLOB`; drop inlined `parse_size`/`get_file_epoch`/inline stat/date)
- Test: `test/test_group.bats` (add naming + media-filter cases; existing cases stay green)

**Interfaces:**
- Consumes from Task 1–2: `WORKFLOW_VERSION`, `PHOTO_GROUP_SIZE`, `is_media_file`, `parse_size`, `stat_size`, `epoch_from_filename_or_fs`, `epoch_to_yymmdd`.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_group.bats`:

```bash
@test "grouped folder is named YYMMDD-YYMMDD-#.#GB with correct dates" {
  make_sparse $((1024 * 1024)) "$TMP/20250101_120000.JPG"
  make_sparse $((1024 * 1024)) "$TMP/20250115_120000.JPG"
  run "$DIR/group_files_size.sh" --size 15G "$TMP"
  [ "$status" -eq 0 ]
  run bash -c "ls -d '$TMP'/*/"
  [[ "$output" =~ 250101-250115-[0-9.]+GB ]]
}

@test "grouping ignores non-media files (leaves them in place)" {
  make_sparse $((1024 * 1024)) "$TMP/20250101_120000.JPG"
  printf 'hello' > "$TMP/notes.txt"
  run "$DIR/group_files_size.sh" --size 15G "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/notes.txt" ]
  run bash -c "ls -d '$TMP'/*/"
  [[ "$output" =~ GB ]]
}

@test "group prints its shared version" {
  run "$DIR/group_files_size.sh" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"group_files_size.sh 1.1.0"* ]]
}
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `bats test/test_group.bats`
Expected: version test FAILS (still prints `1.0.0`); the media-filter test may fail if a `.txt` is currently swept in.

- [ ] **Step 3: Rewrite `group_files_size.sh`**

Replace the top of the file (through the old `parse_size`) with a lib-sourcing header, and replace the body's inlined helpers. Final file:

```bash
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats test/test_group.bats`
Expected: PASS (existing 4 + new 3).

- [ ] **Step 5: Lint & commit**

```bash
shellcheck lib.sh group_files_size.sh
git add group_files_size.sh test/test_group.bats
git commit -m "refactor(group): source lib.sh, filter by is_media_file, share folder glob"
```

---

### Task 4: Rewire `rename_media.sh` onto `lib.sh`

**Files:**
- Modify: `rename_media.sh` (source lib; build `-ext` args from `PHOTO_IMAGE_EXTS`/`PHOTO_VIDEO_EXTS`; tag chains from `PHOTO_DATE_TAGS`/`PHOTO_VIDEO_DATE_TAGS`)
- Test: `test/test_rename.bats` (add PNG-screenshot regression)

**Interfaces:**
- Consumes: `WORKFLOW_VERSION`, `PHOTO_IMAGE_EXTS`, `PHOTO_VIDEO_EXTS`, `PHOTO_DATE_TAGS`, `PHOTO_VIDEO_DATE_TAGS`.

- [ ] **Step 1: Write the failing test**

Append to `test/test_rename.bats`:

```bash
@test "a PNG screenshot (filesystem date only) gets renamed" {
  printf 'x' > "$TMP/Screenshot.PNG"
  touch -t 202501011200.00 "$TMP/Screenshot.PNG"
  run "$DIR/rename_media.sh" "$TMP"
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/Screenshot.PNG" ]
  run bash -c "ls '$TMP'/2*.PNG"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/test_rename.bats`
Expected: FAIL — `.PNG` is not in the v1.0 rename set, so the file is untouched.

- [ ] **Step 3: Rewrite `rename_media.sh`**

Replace the header + the two exiftool blocks. Final file:

```bash
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats test/test_rename.bats`
Expected: PASS (existing rename cases + PNG regression). If `exiftool` is absent, all are skipped — run where it is installed.

- [ ] **Step 5: Lint & commit**

```bash
shellcheck lib.sh rename_media.sh
git add rename_media.sh test/test_rename.bats
git commit -m "refactor(rename): source lib.sh; extensions/tag-chains from PHOTO_* (renames screenshots)"
```

---

### Task 5: `run_mux_motionphoto.sh` — graceful skip + lib

**Files:**
- Modify: `run_mux_motionphoto.sh` (source lib; missing binary → warn + exit 0, not exit 1; version from lib)
- Test: `test/test_cli.bats` (add graceful-skip case)

**Interfaces:**
- Consumes: `WORKFLOW_VERSION`, `PHOTO_OUTPUT_NAME`.
- Produces (for Task 6): exit 0 with a `motionphoto2 not found` warning when the binary is absent.

- [ ] **Step 1: Write the failing test**

Append to `test/test_cli.bats`:

```bash
@test "run_mux warns and skips (exit 0) when motionphoto2 is absent" {
  command -v motionphoto2 >/dev/null 2>&1 && skip "motionphoto2 is installed"
  TMP="$(mktemp -d)"
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/run_mux_motionphoto.sh" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"motionphoto2"* ]]
  rm -rf "$TMP"
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/test_cli.bats`
Expected: on a machine without `motionphoto2`, FAIL (script currently exits 1). On a machine with it, the test is skipped.

- [ ] **Step 3: Rewrite `run_mux_motionphoto.sh`**

```bash
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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats test/test_cli.bats`
Expected: PASS (graceful-skip test passes where `motionphoto2` is absent; skipped where present).

- [ ] **Step 5: Lint & commit**

```bash
shellcheck lib.sh run_mux_motionphoto.sh
git add run_mux_motionphoto.sh test/test_cli.bats
git commit -m "feat(mux): graceful skip when motionphoto2 absent; source lib.sh"
```

---

### Task 6: `masterscript.sh` — universal entry (lib, graceful skip, copy-by-default, `--in-place`, disk-space)

**Files:**
- Modify: `masterscript.sh` (source lib at top; env-backed `SIZE`/`OUTPUT_NAME`; `--in-place` flag; detect missing `motionphoto2` → treat as skip; copy-by-default for the no-mux path; disk-space 2×/1× + resume subtract)
- Test: `test/test_rename.bats` (update the in-place test; add copy + graceful-skip cases)

**Interfaces:**
- Consumes: `WORKFLOW_VERSION`, `PHOTO_GROUP_SIZE`, `PHOTO_OUTPUT_NAME`, `is_media_file`, `dir_size_kb`.
- Produces (for Task 7): the resolved `$TARGET`, `$INPUT_DIR`, `$SKIP_MUX`, `$SIZE`, `$DRY_RUN` state.

- [ ] **Step 1: Update the existing test and add new ones**

In `test/test_rename.bats`, REPLACE the `masterscript --skip-mux --skip-group renames in place` test with:

```bash
@test "masterscript --skip-mux --in-place --skip-group renames originals in place" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/masterscript.sh" --skip-mux --in-place --skip-group "$TMP"
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/IMG_0001.JPG" ]
  run bash -c "ls '$TMP'/2*.JPG"
  [ "$status" -eq 0 ]
}

@test "masterscript --skip-mux copies by default (originals kept)" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/masterscript.sh" --skip-mux --skip-group "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/IMG_0001.JPG" ]
  run bash -c "ls '$TMP'/muxed-photo/2*.JPG"
  [ "$status" -eq 0 ]
}

@test "masterscript with no motionphoto2 skips muxing and still produces output" {
  command -v motionphoto2 >/dev/null 2>&1 && skip "motionphoto2 is installed"
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/masterscript.sh" --skip-group "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/IMG_0001.JPG" ]
  run bash -c "ls '$TMP'/muxed-photo/2*.JPG"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run to verify the new/changed tests fail**

Run: `bats test/test_rename.bats`
Expected: the copy-by-default and no-motionphoto2 tests FAIL (current `--skip-mux` renames in place; `--in-place` flag not yet recognized).

- [ ] **Step 3: Edit `masterscript.sh` — source lib and add the `--in-place` flag**

Near the top, replace the `VERSION="1.0.0"` line and add sourcing BEFORE arg parsing:

```bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" || { echo "Error: lib.sh not found next to $0" >&2; exit 1; }
```

In the defaults block, base `SIZE`/`OUTPUT_NAME` on the env-backed vars and add `IN_PLACE`:

```bash
DRY_RUN=false
SKIP_MUX=false
SKIP_RENAME=false
SKIP_GROUP=false
IN_PLACE=false
OUTPUT_NAME="$PHOTO_OUTPUT_NAME"
SIZE="$PHOTO_GROUP_SIZE"
INPUT_DIR=""
```

In the arg loop, change `--version` to use `WORKFLOW_VERSION` and add `--in-place`:

```bash
    --version) echo "masterscript.sh $WORKFLOW_VERSION"; exit 0 ;;
    --in-place) IN_PLACE=true; shift ;;
```

Add `--in-place` to `usage()` text:

```
  --in-place        When muxing does not run, rename/group the ORIGINALS in place
                    (no output copy). Default is to work on a copy in <output-name>/.
```

- [ ] **Step 4: Edit the disk-space pre-flight for copy/in-place + resume**

Replace the input-size + required-space block with:

```bash
input_size_kb=$(dir_size_kb "$INPUT_DIR")
# On a resume, an existing output copy inflates the input measurement — subtract it.
if [[ -d "$MUXED_DIR" ]]; then
    muxed_kb=$(dir_size_kb "$MUXED_DIR")
    input_size_kb=$((input_size_kb - muxed_kb))
    (( input_size_kb < 0 )) && input_size_kb=0
fi
input_size_gb=$(awk -v kb="$input_size_kb" 'BEGIN {printf "%.1f", kb / (1024*1024)}')
free_space_kb=$(df -Pk "$INPUT_DIR" | awk 'NR==2 {print $4}')
free_space_gb=$(awk -v kb="$free_space_kb" 'BEGIN {printf "%.1f", kb / (1024*1024)}')
# A copy is made unless the no-mux path runs in place.
if [[ "$IN_PLACE" == true ]]; then
    required_gb="$input_size_gb"
else
    required_gb=$(awk -v sz="$input_size_gb" 'BEGIN {printf "%.1f", sz * 2}')
fi
```

- [ ] **Step 5: Edit Step 1 (mux) — graceful detection + copy-by-default**

Replace the whole Step-1 block with:

```bash
# Graceful mux skip: if the binary is missing and muxing wasn't already skipped,
# downgrade to a skip so non-iPhone users can still run rename/group.
if [[ "$SKIP_MUX" == false ]] && ! command -v motionphoto2 &> /dev/null; then
    log "Note: 'motionphoto2' not found — skipping Live-Photo muxing (step 1)."
    SKIP_MUX=true
fi

# Step 1: Mux Live Photos (before rename to preserve original filenames for matching)
if [[ "$SKIP_MUX" == true ]]; then
    if [[ "$IN_PLACE" == true ]]; then
        log "--- Step 1: Muxing skipped; operating IN PLACE on $INPUT_DIR ---"
        [[ "$DRY_RUN" == false ]] && log "Note: originals in $INPUT_DIR will be renamed/moved."
        TARGET="$INPUT_DIR"
    else
        log "--- Step 1: Muxing skipped; copying media into $MUXED_DIR (originals kept) ---"
        if [[ "$DRY_RUN" == true ]]; then
            TARGET="$INPUT_DIR"
            log "DRY RUN: rename/group preview against the input files."
        else
            mkdir -p "$MUXED_DIR"
            copied=0
            while IFS= read -r -d '' f; do
                is_media_file "$f" || continue
                cp -p "$f" "$MUXED_DIR/" && copied=$((copied + 1))
            done < <(find "$INPUT_DIR" -maxdepth 1 -type f ! -name ".*" -print0)
            log "Copied $copied media file(s) into $MUXED_DIR."
            TARGET="$MUXED_DIR"
        fi
    fi
else
    if [[ -f "$CHECKPOINT_MUX" ]]; then
        log "--- Step 1: Skipping muxing (already completed) ---"
    else
        log "--- Step 1: Converting Live Photos ---"
        "$SCRIPT_DIR/run_mux_motionphoto.sh" --output-name "$OUTPUT_NAME" "$INPUT_DIR" 2>&1 | tee -a "$LOG_FILE"
        touch "$CHECKPOINT_MUX"
        log "--- Step 1: Complete ---"
    fi
    if [[ ! -d "$MUXED_DIR" ]]; then
        log "Error: '$MUXED_DIR' was not created by Step 1. Cannot proceed." >&2
        exit 1
    fi
    TARGET="$MUXED_DIR"
fi
```

Note: `--dry-run` still forces `SKIP_MUX=true` earlier in the file (unchanged); in dry-run the copy is not performed and `TARGET="$INPUT_DIR"`, so the preview reads the input files.

- [ ] **Step 6: Run tests to verify they pass**

Run: `bats test/test_rename.bats`
Expected: PASS — in-place test (with `--in-place`), copy-by-default test, and (where `motionphoto2` is absent) the graceful-skip test.

- [ ] **Step 7: Lint & commit**

```bash
shellcheck lib.sh masterscript.sh
git add masterscript.sh test/test_rename.bats
git commit -m "feat(master): graceful mux skip, copy-by-default with --in-place, disk-space fix"
```

---

### Task 7: `masterscript.sh` — per-import summary + ledger

**Files:**
- Modify: `masterscript.sh` (add `--ledger`/`--no-ledger`; write summary + TSV row before final cleanup)
- Test: `test/test_rename.bats` (add ledger cases)

**Interfaces:**
- Consumes: `$TARGET`, `$INPUT_DIR`, `$SKIP_MUX`, `PHOTO_LEDGER`, `is_media_file`, `is_image_file`, `dir_size_kb`, `epoch_from_filename_or_fs`, `epoch_to_ymd`, `GROUP_FOLDER_GLOB`.

- [ ] **Step 1: Write the failing tests**

Append to `test/test_rename.bats`:

```bash
@test "masterscript writes a summary and a ledger row inside the target" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/masterscript.sh" --skip-mux --skip-group "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Summary:"* ]]
  [ -f "$TMP/muxed-photo/library-ledger.tsv" ]
  run bash -c "wc -l < '$TMP/muxed-photo/library-ledger.tsv' | tr -d ' '"
  [ "$output" = "2" ]   # header + one row
}

@test "masterscript --no-ledger writes no ledger" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/masterscript.sh" --skip-mux --skip-group --no-ledger "$TMP"
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/muxed-photo/library-ledger.tsv" ]
}

@test "masterscript --dry-run writes no ledger" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/masterscript.sh" --dry-run "$TMP"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/muxed-photo" ]
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `bats test/test_rename.bats`
Expected: FAIL — no summary line, no ledger file, `--no-ledger` unrecognized.

- [ ] **Step 3: Add the flags**

In the arg loop add:

```bash
    --ledger)
      LEDGER_PATH="${2:-}"
      [[ -z "$LEDGER_PATH" ]] && { echo "Error: --ledger requires a path" >&2; exit 1; }
      shift 2 ;;
    --no-ledger) NO_LEDGER=true; shift ;;
```

In the defaults block add:

```bash
LEDGER_PATH=""
NO_LEDGER=false
```

Add to `usage()`:

```
  --ledger PATH     Append a per-import summary row to PATH (default: a
                    library-ledger.tsv inside the results directory; or PHOTO_LEDGER).
  --no-ledger       Do not write a ledger row for this run.
```

- [ ] **Step 4: Add the summary/ledger function and call it**

Add this function after `log()` is defined:

```bash
write_summary_and_ledger() {
    local images=0 videos=0 total=0 min_epoch="" max_epoch="" e f
    while IFS= read -r -d '' f; do
        is_media_file "$f" || continue
        total=$((total + 1))
        if is_image_file "$f"; then images=$((images + 1)); else videos=$((videos + 1)); fi
        e=$(epoch_from_filename_or_fs "$f")
        if [[ -z "$min_epoch" ]] || (( e < min_epoch )); then min_epoch=$e; fi
        if [[ -z "$max_epoch" ]] || (( e > max_epoch )); then max_epoch=$e; fi
    done < <(find "$TARGET" -type f ! -name ".*" -print0)

    local date_from="-" date_to="-"
    [[ -n "$min_epoch" ]] && date_from=$(epoch_to_ymd "$min_epoch")
    [[ -n "$max_epoch" ]] && date_to=$(epoch_to_ymd "$max_epoch")

    local batches=0 d
    for d in "$TARGET"/$GROUP_FOLDER_GLOB; do [[ -d "$d" ]] && batches=$((batches + 1)); done

    local total_size_gb
    total_size_gb=$(awk -v kb="$(dir_size_kb "$TARGET")" 'BEGIN {printf "%.1f", kb / (1024*1024)}')

    local motion_photos="-"
    if [[ "$SKIP_MUX" == false ]] && command -v exiftool &> /dev/null; then
        motion_photos=$(exiftool -q -q -if '$XMP-GCamera:MotionPhoto' -p '1' -r "$TARGET" 2>/dev/null | wc -l | tr -d ' ')
    fi

    log "Summary: $date_from..$date_to | images=$images videos=$videos motion=$motion_photos files=$total size=${total_size_gb}GB batches=$batches"

    if [[ "$NO_LEDGER" == true ]]; then return 0; fi
    local ledger
    if [[ -n "$LEDGER_PATH" ]]; then ledger="$LEDGER_PATH"
    elif [[ -n "$PHOTO_LEDGER" ]]; then ledger="$PHOTO_LEDGER"
    else ledger="$TARGET/library-ledger.tsv"; fi

    if [[ ! -f "$ledger" ]]; then
        printf 'run_completed_at\timport_dir\ttarget_dir\tdate_from\tdate_to\timages\tvideos\tmotion_photos\ttotal_files\ttotal_size_gb\tbatches\n' > "$ledger"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$INPUT_DIR" "$TARGET" "$date_from" "$date_to" \
        "$images" "$videos" "$motion_photos" "$total" "$total_size_gb" "$batches" >> "$ledger"
    log "Ledger updated: $ledger"
}
```

Call it just before the checkpoint cleanup in the success path (after `log "--- Workflow complete ---"` and the results log lines, before `rm -rf "$WORK_DIR"`):

```bash
write_summary_and_ledger
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats test/test_rename.bats`
Expected: PASS (summary printed, ledger row written, `--no-ledger`/`--dry-run` write none).

- [ ] **Step 6: Lint & commit**

```bash
shellcheck lib.sh masterscript.sh
git add masterscript.sh test/test_rename.bats
git commit -m "feat(master): per-import summary + library ledger (--ledger/--no-ledger)"
```

---

### Task 8: `ungroup.sh` — source lib + shared folder glob

**Files:**
- Modify: `ungroup.sh` (source lib; iterate `GROUP_FOLDER_GLOB`; version from lib)
- Test: covered by the existing round-trip test in `test/test_group.bats`.

**Interfaces:**
- Consumes: `WORKFLOW_VERSION`, `GROUP_FOLDER_GLOB`.

- [ ] **Step 1: Write the failing test**

Append to `test/test_cli.bats`:

```bash
@test "ungroup prints its shared version" {
  run "$DIR/ungroup.sh" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"ungroup.sh 1.1.0"* ]]
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `bats test/test_cli.bats`
Expected: FAIL — still prints `1.0.0`.

- [ ] **Step 3: Edit `ungroup.sh`**

Add sourcing after `set -euo pipefail` (replace the `VERSION="1.0.0"` line):

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh" || { echo "Error: lib.sh not found next to $0" >&2; exit 1; }
```

Change the `--version` case body to:

```bash
        echo "ungroup.sh $WORKFLOW_VERSION"
```

Change the folder loop from the hardcoded glob to the shared constant:

```bash
for folder in $GROUP_FOLDER_GLOB; do
    [[ -d "$folder" ]] || continue
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats test`
Expected: PASS — full suite, including the existing group→ungroup round-trip.

- [ ] **Step 5: Lint & commit**

```bash
shellcheck lib.sh ungroup.sh
git add ungroup.sh test/test_cli.bats
git commit -m "refactor(ungroup): source lib.sh; use shared GROUP_FOLDER_GLOB"
```

---

### Task 9: README, changelog, and CI badge

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Full green gate**

Run: `shellcheck *.sh && bats test`
Expected: shellcheck clean; all tests pass (exiftool-dependent ones run where installed).

- [ ] **Step 2: Update the README**

Make these edits to `README.md`:
1. Under **Requirements**, note muxing now auto-skips if `motionphoto2` is absent (no longer required to run at all).
2. Add a **Configuration (env overrides)** subsection documenting each `PHOTO_*` var, the flag→env→default precedence, and that there is no config file by design. Example:
   ```sh
   PHOTO_GROUP_SIZE=50G PHOTO_OUTPUT_NAME=organized ./masterscript.sh /path/to/photos
   ```
3. Document the new flags in the `masterscript.sh` options block: `--in-place`, `--ledger PATH`, `--no-ledger`.
4. Add a **Behavior changes in v1.1** note: screenshots/all media renamed; grouping moves only media; `--skip-mux` now works on a copy by default (`--in-place` for the old behavior); missing `motionphoto2` warns-and-skips; new summary + `library-ledger.tsv` (inside the target; use `--ledger`/`PHOTO_LEDGER` to point elsewhere).
5. Add a `## Configuration` note that the grouped-folder name pattern and EXIF tag ORDER are intentionally fixed.
6. If the GitHub Actions run is green (check the repo's **Actions** tab), add the badge under the title and remove the deferred follow-up note:
   ```
   ![CI](https://github.com/leongyeehang/iphone-pixel-google-photo-import/actions/workflows/ci.yml/badge.svg)
   ```
7. Add a `### 2026-07-23 (v1.1) — universal solution` changelog entry summarizing the above.

- [ ] **Step 3: Verify docs match reality**

Run: `./masterscript.sh --help && ./group_files_size.sh --help`
Expected: help text matches the README options (spot-check `--in-place`, `--ledger`, `--size`).

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: document universal config (env overrides), new flags, v1.1 changelog + CI badge"
```

---

## Self-Review

**Spec coverage:**
- Env-idiom config layer → Task 1 (defaults) + used throughout. ✓
- Single media source of truth (screenshot bug) → Task 1 (`is_media_file`) + Task 3 (group) + Task 4 (rename). ✓
- `FileModifyDate` photo fallback → Task 1 (`PHOTO_DATE_TAGS` default) + Task 4. ✓
- Graceful mux skip → Task 5 (script) + Task 6 (master detection). ✓
- Copy-by-default + `--in-place` + disk-space (2×/1× + resume subtract) → Task 6. ✓
- Ledger inside target + `--ledger`/`--no-ledger` + fixed columns + dry-run writes none → Task 7. ✓
- Shared folder glob (group creates / ungroup globs) → Task 1 constant + Task 3 + Task 8. ✓
- Version consolidation → Tasks 3–8. ✓
- Deeper tests (naming, size suffix, resume, PNG, env override, ledger, copy vs in-place, graceful skip) → Tasks 1–7. ✓
- Resume checkpoints test → **GAP** noted: the spec listed a checkpoint-skip test; it is not strictly required for v1.1 behavior and the checkpoint code is unchanged, but add it opportunistically in Task 7's test file if time permits (pre-seed `.workflow/.rename_done`, assert "Skipping rename (already completed)").
- README/changelog/CI badge → Task 9. ✓

**Placeholder scan:** No TBD/TODO; every code step shows full code; every test step shows real assertions. ✓

**Type/name consistency:** `is_media_file`/`is_image_file`/`is_video_file`, `parse_size`, `stat_size`, `epoch_from_filename_or_fs`, `epoch_to_yymmdd`, `epoch_to_ymd`, `dir_size_kb`, `GROUP_FOLDER_GLOB`, `WORKFLOW_VERSION`, `PHOTO_*` names are used identically across Tasks 1–9. ✓

**Note on the resume-checkpoint test:** promote it into Task 7 Step 1 as a fourth case if the executing agent wants full spec parity:
```bash
@test "masterscript skips an already-completed rename checkpoint" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  mkdir -p "$TMP/.workflow"; touch "$TMP/.workflow/.rename_done"
  run "$DIR/masterscript.sh" --skip-mux --in-place --skip-group "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping rename (already completed)"* ]]
}
```
