#!/usr/bin/env bash

# verify_residue.sh: Account for the files Google Photos' "Free up space" left on the
# device, and show whether they are safe to delete.
# Usage: ./tools/verify_residue.sh [options] <residue_directory> <batch_directory>
#
# "Free up space" does not clear a whole Batch, and that is normal: measured on this
# library, ~82% of HEIC muxed output and ~13% of JPEG muxed output survives a fully
# confirmed backup, while non-Motion-Photos are reclaimed without exception.
#
# So residue by itself proves nothing. This checks the two things that would NOT be
# normal:
#   1. a plain (non-Motion-Photo) file left behind - measured at 0 of 527, so it is the
#      one pattern that genuinely suggests files did not upload;
#   2. a leftover whose bytes do not match its master in the Batch.
#
# See docs/WORKFLOW.md - "`Free up space` leaves Motion Photos behind".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR/..
# shellcheck source=lib.sh
. "$SCRIPT_DIR/../lib.sh" || { echo "Error: lib.sh not found above $0" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: verify_residue.sh [options] <residue_directory> <batch_directory>

Compare the files "Free up space" left on the Pixel against the Batch that was pushed.

  <residue_directory>  the leftovers, pulled back off the phone
  <batch_directory>    the Batch as it was transferred, in the Results directory

Reports what stayed behind by class (Motion Photo vs plain, by container), and verifies
every leftover is byte-identical to its master on the Mac.

Both directories are read non-recursively, and neither is modified.

Options:
  --no-hash     Skip the byte-for-byte integrity check (much faster on a large Batch).
  -h, --help    Show this help and exit.
      --version Print version and exit.

Exit status:
  0  residue is consistent with the known "Free up space" behaviour - safe to delete
  1  usage or setup error
  2  something needs attention (a plain file left behind, or a content mismatch)

Example:
  ./tools/verify_residue.sh ~/pixel-leftovers/260415-260503-9.8GB \
      ~/lib/2026July28/muxed-photo/260415-260503-9.8GB
EOF
}

NO_HASH=false
RESIDUE_DIR=""
BATCH_DIR=""

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --version) echo "verify_residue.sh $WORKFLOW_VERSION"; exit 0 ;;
        --no-hash) NO_HASH=true; shift ;;
        -*) echo "Error: unknown option '$1'" >&2; usage >&2; exit 1 ;;
        *)
            if [[ -z "$RESIDUE_DIR" ]]; then RESIDUE_DIR="$1"
            elif [[ -z "$BATCH_DIR" ]]; then BATCH_DIR="$1"
            else echo "Error: unexpected argument '$1'" >&2; exit 1
            fi
            shift ;;
    esac
done

if [[ -z "$RESIDUE_DIR" || -z "$BATCH_DIR" ]]; then
    echo "Usage: $0 [options] <residue_directory> <batch_directory>" >&2
    exit 1
fi
for d in "$RESIDUE_DIR" "$BATCH_DIR"; do
    if [[ ! -d "$d" ]]; then echo "Error: directory '$d' not found." >&2; exit 1; fi
done
if ! command -v exiftool &> /dev/null; then
    echo "Error: exiftool is not installed. Install via 'brew install exiftool' (macOS) or 'apt-get install libimage-exiftool-perl' (Linux)." >&2
    exit 1
fi

RESIDUE_DIR="$(cd "$RESIDUE_DIR" && pwd)"
BATCH_DIR="$(cd "$BATCH_DIR" && pwd)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# sha256, portable: shasum ships with macOS, sha256sum with coreutils.
file_hash() {
    if command -v shasum &> /dev/null; then shasum -a 256 "$1" | awk '{print $1}'
    else sha256sum "$1" | awk '{print $1}'; fi
}

# Media only, non-recursive, dotfiles excluded - the same rule the rest of the toolkit uses.
list_media() {
    local f
    while IFS= read -r -d '' f; do
        # NB: a bare `is_media_file "$f" && basename "$f"` returns 1 on a non-media file,
        # which trips `set -e` and silently truncates the listing at the first ledger/log.
        if is_media_file "$f"; then basename "$f"; fi
    done < <(find "$1" -maxdepth 1 -type f ! -name '.*' -print0) | LC_ALL=C sort
}

list_media "$RESIDUE_DIR" > "$WORK/residue.txt"
list_media "$BATCH_DIR"   > "$WORK/batch.txt"

pushed=$(wc -l < "$WORK/batch.txt" | tr -d ' ')
left=$(wc -l < "$WORK/residue.txt" | tr -d ' ')

if [[ "$pushed" -eq 0 ]]; then
    echo "Error: no media files found in Batch directory '$BATCH_DIR'." >&2
    exit 1
fi
reclaimed=$((pushed - left))

# Motion Photo flag + container for every file in the Batch, in one exiftool pass.
# shellcheck disable=SC2016  # single quotes are exiftool's own -p syntax, not shell expansion
exiftool -q -q -f -p '$FileName|$XMP-GCamera:MotionPhoto|$MIMEType' "$BATCH_DIR" \
    2>/dev/null > "$WORK/meta.txt" || true

echo "Residue check: $(basename "$RESIDUE_DIR")"
printf '  Batch pushed:    %6s files\n' "$pushed"
if [[ "$pushed" -gt 0 ]]; then
    pct=$(awk -v l="$left" -v p="$pushed" 'BEGIN {printf "%.1f", 100*l/p}')
    printf '  Left on device:  %6s files (%s%%)\n' "$left" "$pct"
else
    printf '  Left on device:  %6s files\n' "$left"
fi
printf '  Reclaimed:       %6s files\n' "$reclaimed"
echo

# Class each Batch file, then split by whether it is still on the device.
# Class is "<CONTAINER> Motion Photo" for muxed output, "plain" for everything else -
# the split that actually predicts the behaviour.
awk -F'|' -v resfile="$WORK/residue.txt" '
  BEGIN { while ((getline n < resfile) > 0) if (n != "") res[n] = 1 }
  $1 == "" { next }
  {
    split($3, m, "/")
    sub(/^x-adobe-/, "", m[2])
    cls = ($2 == "1") ? toupper(m[2]) " Motion Photo" : "plain"
    total[cls]++
    if ($1 in res) stuck[cls]++
    if ($1 in res && $2 != "1") plain_left++
  }
  END {
    printf "Left behind, by class:\n"
    printf "  %-22s %7s %7s %7s\n", "CLASS", "LEFT", "PUSHED", "RATE"
    for (c in total) {
      s = (c in stuck) ? stuck[c] : 0
      printf "  %-22s %7d %7d %6.1f%%\n", c, s, total[c], 100*s/total[c]
    }
    print (plain_left ? plain_left : 0) > "'"$WORK/plain_left"'"
  }
' "$WORK/meta.txt" | {
    # Keep the two header lines in place and sort only the rows below them.
    # IFS= matters: a bare `read` would strip the leading indent off the column header.
    IFS= read -r hdr; echo "$hdr"
    IFS= read -r cols; echo "$cols"
    LC_ALL=C sort
}

plain_left=$(cat "$WORK/plain_left" 2>/dev/null || echo 0)

# Any leftover the Batch does not account for at all.
unknown=$(LC_ALL=C comm -23 "$WORK/residue.txt" "$WORK/batch.txt" | wc -l | tr -d ' ')

identical=0; differing=0
if [[ "$NO_HASH" == false ]]; then
    echo
    echo "Integrity (leftover vs its master in the Batch):"
    while IFS= read -r n; do
        [[ -z "$n" ]] && continue
        [[ -f "$BATCH_DIR/$n" ]] || continue
        if [[ "$(file_hash "$RESIDUE_DIR/$n")" == "$(file_hash "$BATCH_DIR/$n")" ]]; then
            identical=$((identical + 1))
        else
            differing=$((differing + 1))
            echo "  DIFFERS: $n"
        fi
    done < "$WORK/residue.txt"
    printf '  %-20s %6d\n' "identical" "$identical"
    printf '  %-20s %6d\n' "differing" "$differing"
fi
printf '  %-20s %6d\n' "not in the Batch" "$unknown"
if [[ "$unknown" -gt 0 ]]; then
    LC_ALL=C comm -23 "$WORK/residue.txt" "$WORK/batch.txt" | sed 's/^/  NOT IN BATCH: /'
fi

echo
status=0
if [[ "$plain_left" -gt 0 ]]; then
    echo "ATTENTION: $plain_left non-Motion-Photo file(s) left on the device."
    echo "  Measured rate for these is 0 of 527, so this is the one pattern that suggests"
    echo "  files did not actually upload. Re-confirm the backup (WORKFLOW.md Stage 6)"
    echo "  before deleting anything."
    status=2
fi
if [[ "$differing" -gt 0 ]]; then
    echo "ATTENTION: $differing leftover(s) do not match their master in the Batch."
    echo "  The device copy is not the file you pushed. Investigate before deleting."
    status=2
fi
if [[ "$unknown" -gt 0 ]]; then
    echo "ATTENTION: $unknown leftover(s) are not in this Batch at all."
    echo "  Either the wrong Batch was passed, or the device holds files from elsewhere."
    status=2
fi

if [[ "$status" -eq 0 ]]; then
    if [[ "$left" -eq 0 ]]; then
        echo "OK: nothing left on the device - the whole Batch was reclaimed."
    else
        echo "OK: every leftover is a Motion Photo$([[ "$NO_HASH" == false ]] && echo ", byte-identical to its master")."
        echo "  Expected behaviour, not a failed upload. Safe to delete from the device by hand."
    fi
fi
exit "$status"
