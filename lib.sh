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
# Keys:CreationDate is last on purpose: QuickTime:CreateDate & friends are stored in UTC with
# no offset, so on their own they name videos in UTC while stills are named in local time
# (8 h apart in SGT). Keys:CreationDate carries the local time plus its offset, which realigns
# videos with their stills — and keeps a Live Photo pair sharing a base name, so muxing still
# works if --exif-match is ever dropped. Videos lacking it fall back to the UTC tags.
: "${PHOTO_VIDEO_DATE_TAGS:=FileModifyDate FileCreateDate TrackCreateDate MediaCreateDate QuickTime:CreateDate Keys:CreationDate}"
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

# --- exiftool stderr classification -------------------------------------------
# exiftool labels almost everything "Warning:", including real failures such as
# "Warning: Error opening file" - so the prefix cannot separate noise from harm.
# These two notices are emitted by this pipeline's OWN correct output on every run:
#   "Google trailer MotionPhoto video/quicktime not handled"  - each muxed JPG Motion Photo
#   "[minor] The ExtractEmbedded option may find more tags"   - each video
#   "File name is unchanged"                                  - re-running over renamed files
# The last one makes a repeat run idempotent rather than alarming: the computed name simply
# already matches. Anything else in the log is treated as a problem worth surfacing.
EXIFTOOL_BENIGN_RE='Google trailer MotionPhoto|ExtractEmbedded option may find|File name is unchanged'

benign_notice_count() {
    [[ -f "$1" ]] || { echo 0; return 0; }
    grep -cE "$EXIFTOOL_BENIGN_RE" "$1" 2>/dev/null || true
}

# Count only actual messages. exiftool also writes run summaries to stderr
# ("1 directories scanned", "0 image files read"), which are not problems.
message_line_count() {
    [[ -f "$1" ]] || { echo 0; return 0; }
    grep -cE '^(Warning|Error)' "$1" 2>/dev/null || true
}

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
