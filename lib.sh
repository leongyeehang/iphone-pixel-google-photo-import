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
