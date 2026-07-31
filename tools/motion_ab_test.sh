#!/usr/bin/env bash
# motion_ab_test.sh — A/B experiment: can Motion Photo playback be made to look more like
# the iPhone Live Photo? Builds 5 variants of each of N source Live Photos, muxes each, and
# verifies the results. Throwaway diagnostic; promote to script/tools/ only if a variant wins.
#
# READ-ONLY with respect to the photo library. Everything is written under $WORK.
#
# Usage: ./motion_ab_test.sh [-n CLIPS] [-s SAMPLE] [-d SRC_DIR] [base ...]

set -euo pipefail

SRC_DIR="/Volumes/Aca_WD/media/Import from Image Capture/Import2here/Leong/iphone_photos"
# Deliberately OUTSIDE the repo: a run writes ~100 MB of HEIC. Override with MOTION_AB_WORK.
WORK="${MOTION_AB_WORK:-/Volumes/Aca_WD/media/Import from Image Capture/motion-ab-test}"
N_CLIPS=3
SAMPLE=30
BITRATE="12M"
TRIM_PAD=0.6          # seconds either side of the still marker for V4
EXPLICIT_BASES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n) N_CLIPS="$2"; shift 2 ;;
    -s) SAMPLE="$2"; shift 2 ;;
    -d) SRC_DIR="$2"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) EXPLICIT_BASES+=("$1"); shift ;;
  esac
done

for c in ffmpeg ffprobe exiftool motionphoto2; do
  command -v "$c" >/dev/null || { echo "Error: $c not found" >&2; exit 1; }
done
[[ -d "$SRC_DIR" ]] || { echo "Error: source '$SRC_DIR' not found" >&2; exit 1; }

rm -rf "$WORK"; mkdir -p "$WORK/work" "$WORK/upload"
REPORT="$WORK/report.tsv"
printf 'clip\tvariant\tdims\trotation\tstill_us\tduration_s\tsize_mb\tmotion_photo\tstatus\n' > "$REPORT"

# --- helpers -----------------------------------------------------------------

# Mean frame-to-frame luma difference. Higher = more camera movement.
motion_score() {
    local t; t=$(mktemp)
    ffmpeg -v error -noautorotate -i "$1" \
        -vf "scale=240:-1,tblend=all_mode=difference,signalstats,metadata=print:file=$t:key=lavfi.signalstats.YAVG" \
        -f null - 2>/dev/null || true
    awk -F= '/YAVG/{s+=$2;c++} END{if(c) printf "%.4f", s/c; else printf "0"}' "$t"
    rm -f "$t"
}

# Offset of Apple's still-image marker, in seconds. Empty if absent.
# NOTE: -ee (ExtractEmbedded) is REQUIRED — StillImageTime lives in a metadata track and is
# invisible without it. Omitting it silently yields "no marker" for every clip.
still_offset_s() {
    local grp
    grp=$(exiftool -ee -a -G1 -s -StillImageTime "$1" 2>/dev/null | sed -n '1s/^\[\([^]]*\)\].*/\1/p')
    [[ -z "$grp" ]] && return 0
    exiftool -n -a -G1 -s -TrackDuration "$1" 2>/dev/null | awk -v g="[$grp]" '$1==g {print $NF; exit}'
}

sec_to_us() { awk -v s="$1" 'BEGIN{printf "%d", s*1000000}'; }

# --- 1. choose source clips --------------------------------------------------

BASES=()
if [[ ${#EXPLICIT_BASES[@]} -gt 0 ]]; then
    BASES=("${EXPLICIT_BASES[@]}")
    echo "Using clips named on the command line: ${BASES[*]}"
else
    echo "Scoring up to $SAMPLE pairs for camera motion (this takes a minute)..."
    scored=$(mktemp)
    n=0
    while IFS= read -r h; do
        b="${h%.HEIC}"
        [[ -f "$SRC_DIR/$b.MOV" ]] || continue
        n=$((n + 1)); [[ $n -gt $SAMPLE ]] && break
        printf '%s\t%s\n' "$(motion_score "$SRC_DIR/$b.MOV")" "$b" >> "$scored"
    done < <(cd "$SRC_DIR" && ls -- *.HEIC 2>/dev/null)

    sort -n "$scored" -o "$scored"
    total=$(wc -l < "$scored" | tr -d ' ')
    [[ "$total" -lt 1 ]] && { echo "No Live Photo pairs found in $SRC_DIR" >&2; exit 1; }
    # lowest / median / highest motion, so the panel spans the range
    for frac in 1 $(( (total + 1) / 2 )) "$total"; do
        BASES+=("$(sed -n "${frac}p" "$scored" | cut -f2)")
    done
    echo "Motion scores (low → high):"; column -t -s $'\t' "$scored" | sed 's/^/  /'
    rm -f "$scored"
    # de-duplicate while preserving order, then trim to N_CLIPS
    uniq_bases=(); for b in "${BASES[@]}"; do
        skip=false; for u in ${uniq_bases[@]+"${uniq_bases[@]}"}; do [[ "$u" == "$b" ]] && skip=true; done
        [[ "$skip" == false ]] && uniq_bases+=("$b")
    done
    BASES=("${uniq_bases[@]:0:$N_CLIPS}")
fi
echo "Selected: ${BASES[*]}"; echo

# --- 2. build and mux the variants -------------------------------------------

mux_and_record() {
    # $1 base  $2 variant  $3 video  $4 still_us (may be empty)  $5 expected_rotation
    local base="$1" variant="$2" video="$3" us="$4" want_rot="$5"
    local still="$WORK/work/$base/$base.HEIC"
    local out="$WORK/upload/${base}_${variant}.HEIC"
    local status="ok"

    if ! motionphoto2 --input-image "$still" --input-video "$video" --output-file "$out" \
         >/dev/null 2>&1 || [[ ! -f "$out" ]]; then
        printf '%s\t%s\t-\t-\t-\t-\t-\t-\tMUX FAILED\n' "$base" "$variant" >> "$REPORT"
        echo "  $variant: MUX FAILED"; return 0
    fi

    # Re-encoding strips Apple's marker track, so motionphoto2 cannot derive the
    # presentation timestamp. Write it back explicitly. (Risk #1 from the plan.)
    if [[ -n "$us" ]]; then
        exiftool -overwrite_original -q \
            "-XMP-GCamera:MotionPhotoPresentationTimestampUs=$us" "$out" 2>/dev/null || true
    fi

    local got_us got_rot dims dur size ismp
    got_us=$(exiftool -s3 -MotionPhotoPresentationTimestampUs "$out" 2>/dev/null)
    got_rot=$(exiftool -s3 -Rotation "$video" 2>/dev/null)
    dims=$(exiftool -s3 -ImageSize "$video" 2>/dev/null)
    dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$video" 2>/dev/null)
    size=$(awk -v b="$(stat -f%z "$out")" 'BEGIN{printf "%.1f", b/1048576}')
    ismp=$(exiftool -s3 -MotionPhoto "$out" 2>/dev/null)

    [[ "$ismp" != "1" ]] && status="NOT A MOTION PHOTO"
    [[ -n "$want_rot" && "$got_rot" != "$want_rot" ]] && status="ROTATION DRIFT ($got_rot vs $want_rot)"
    # motionphoto2 writes -1 when it cannot find Apple's marker (i.e. after a re-encode).
    # A non-positive or out-of-range value is a FAILURE, not a pass — checking only for
    # emptiness let every re-encoded variant through as "ok" on the first run.
    if ! [[ "$got_us" =~ ^[0-9]+$ ]]; then
        status="BAD TIMESTAMP (${got_us:--})"
    elif [[ -n "$dur" ]] && awk -v u="$got_us" -v d="$dur" 'BEGIN{exit !(u > d*1000000)}'; then
        status="TIMESTAMP PAST END (${got_us}us > ${dur}s)"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$base" "$variant" "$dims" "$got_rot" "${got_us:--}" "$dur" "$size" "${ismp:-0}" "$status" >> "$REPORT"
    echo "  $variant: $dims rot=$got_rot ts=${got_us:--}us ${size}MB — $status"
}

for base in "${BASES[@]}"; do
    d="$WORK/work/$base"; mkdir -p "$d"
    cp "$SRC_DIR/$base.HEIC" "$SRC_DIR/$base.MOV" "$d/"       # copies only; source untouched
    orig="$d/$base.MOV"

    rot=$(exiftool -s3 -Rotation "$orig" 2>/dev/null)
    clean=$(exiftool -s3 -CleanApertureDimensions "$orig" 2>/dev/null)
    cw=${clean%x*}; ch=${clean#*x}
    dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$orig")
    soff=$(still_offset_s "$orig")
    sus=""; [[ -n "$soff" ]] && sus=$(sec_to_us "$soff")

    echo "=== $base  rot=$rot  clean=${clean:-none}  dur=${dur}s  still@${soff:-?}s ==="

    # V0 — control, untouched
    mux_and_record "$base" "V0-control" "$orig" "$sus" "$rot"

    # V1 — crop to the clean aperture (targets edge distortion)
    if [[ -n "$cw" && -n "$ch" && "$clean" == *x* ]]; then
        ffmpeg -v error -noautorotate -i "$orig" -vf "crop=$cw:$ch" \
            -c:v hevc_videotoolbox -b:v "$BITRATE" -c:a copy \
            -metadata:s:v:0 rotate="$rot" "$d/v1.mov" -y
        mux_and_record "$base" "V1-crop" "$d/v1.mov" "$sus" "$rot"
    else
        echo "  V1-crop: skipped (no clean aperture)"
    fi

    # V2 — stabilise (targets left-right wobble)
    ffmpeg -v error -noautorotate -i "$orig" \
        -vf "vidstabdetect=shakiness=8:accuracy=15:result=$d/v2.trf" -f null - 2>/dev/null
    ffmpeg -v error -noautorotate -i "$orig" \
        -vf "vidstabtransform=input=$d/v2.trf:smoothing=15:crop=black,unsharp=5:5:0.6:3:3:0.3" \
        -c:v hevc_videotoolbox -b:v "$BITRATE" -c:a copy \
        -metadata:s:v:0 rotate="$rot" "$d/v2.mov" -y
    mux_and_record "$base" "V2-stab" "$d/v2.mov" "$sus" "$rot"

    # V3 — crop + stabilise
    if [[ -f "$d/v1.mov" ]]; then
        ffmpeg -v error -noautorotate -i "$d/v1.mov" \
            -vf "vidstabdetect=shakiness=8:accuracy=15:result=$d/v3.trf" -f null - 2>/dev/null
        ffmpeg -v error -noautorotate -i "$d/v1.mov" \
            -vf "vidstabtransform=input=$d/v3.trf:smoothing=15:crop=black,unsharp=5:5:0.6:3:3:0.3" \
            -c:v hevc_videotoolbox -b:v "$BITRATE" -c:a copy \
            -metadata:s:v:0 rotate="$rot" "$d/v3.mov" -y
        mux_and_record "$base" "V3-crop-stab" "$d/v3.mov" "$sus" "$rot"
    fi

    # V4 — trim to a tight window around the still marker (targets framing travel)
    if [[ -n "$soff" ]]; then
        start=$(awk -v s="$soff" -v p="$TRIM_PAD" 'BEGIN{v=s-p; print (v<0)?0:v}')
        end=$(awk -v s="$soff" -v p="$TRIM_PAD" -v d="$dur" 'BEGIN{v=s+p; print (v>d)?d:v}')
        new_us=$(awk -v s="$soff" -v st="$start" 'BEGIN{printf "%d",(s-st)*1000000}')
        ffmpeg -v error -noautorotate -i "$orig" -ss "$start" -to "$end" \
            -c:v hevc_videotoolbox -b:v "$BITRATE" -c:a copy \
            -metadata:s:v:0 rotate="$rot" "$d/v4.mov" -y
        mux_and_record "$base" "V4-trim" "$d/v4.mov" "$new_us" "$rot"
    else
        echo "  V4-trim: skipped (no still marker in source)"
    fi
    echo
done

# --- 3. report ---------------------------------------------------------------

echo "================ RESULTS ================"
column -t -s $'\t' "$REPORT"
echo
fails=$(awk -F'\t' 'NR>1 && $9!="ok"' "$REPORT" | wc -l | tr -d ' ')
echo "Variants built : $(( $(wc -l < "$REPORT") - 1 ))"
echo "Problems       : $fails"
echo "Upload these   : $WORK/upload"
echo
echo "Next: push $WORK/upload to the Pixel (OpenMTP → Internal Storage/DCIM/, or"
echo "      adb push \"$WORK/upload\" /sdcard/DCIM/ && adb reboot), enable backup for the"
echo "      folder in Google Photos, then compare each variant against the iPhone original."
