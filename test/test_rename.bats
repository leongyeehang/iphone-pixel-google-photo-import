#!/usr/bin/env bats
#
# Rename + skip-flag integration. Needs exiftool; skipped automatically if absent.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  command -v exiftool >/dev/null 2>&1 || skip "exiftool not installed"
  TMP="$(mktemp -d)"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

@test "rename --dry-run previews, changes nothing, and leaves no .workflow" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/rename_media.sh" --dry-run "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/IMG_0001.JPG" ]
  [ ! -e "$TMP/.workflow" ]
}

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

@test "masterscript --dry-run makes no changes" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/masterscript.sh" --dry-run "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/IMG_0001.JPG" ]
  [ ! -e "$TMP/.workflow" ]
  [ ! -e "$TMP/muxed-photo" ]
}

@test "a PNG screenshot (filesystem date only) gets renamed" {
  printf 'x' > "$TMP/Screenshot.PNG"
  touch -t 202501011200.00 "$TMP/Screenshot.PNG"
  run "$DIR/rename_media.sh" "$TMP"
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/Screenshot.PNG" ]
  run bash -c "ls '$TMP'/2*.PNG"
  [ "$status" -eq 0 ]
}

@test "a video is renamed in local time, not UTC, so it aligns with its still" {
  command -v ffmpeg >/dev/null 2>&1 || skip "ffmpeg not installed"
  ffmpeg -v error -f lavfi -i testsrc=d=1:s=64x64 -c:v libx264 -t 0.5 \
    -pix_fmt yuv420p "$TMP/clip.mov" -y
  # Same instant, two tags: QuickTime:CreateDate is UTC, Keys:CreationDate is local +08:00.
  exiftool -overwrite_original -q \
    -QuickTime:CreateDate="2026:04:15 11:43:06" \
    -Keys:CreationDate="2026:04:15 19:43:06+08:00" "$TMP/clip.mov"

  run "$DIR/rename_media.sh" "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/20260415_194306.mov" ]     # local time
  [ ! -f "$TMP/20260415_114306.mov" ]   # not UTC
}

@test "masterscript skips an already-completed rename checkpoint" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  mkdir -p "$TMP/.workflow"; touch "$TMP/.workflow/.rename_done"
  run "$DIR/masterscript.sh" --skip-mux --in-place --skip-group "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipping rename (already completed)"* ]]
}

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

@test "masterscript --skip-mux skips the copy when the checkpoint exists (resume)" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  mkdir -p "$TMP/muxed-photo"
  cp -p "$TMP/IMG_0001.JPG" "$TMP/muxed-photo/20250101_120000.JPG"
  mkdir -p "$TMP/.workflow"; touch "$TMP/.workflow/.mux_done" "$TMP/.workflow/.rename_done"
  run "$DIR/masterscript.sh" --skip-mux "$TMP"
  [ "$status" -eq 0 ]
  run bash -c "find '$TMP/muxed-photo' -name IMG_0001.JPG | wc -l | tr -d ' '"
  [ "$output" = "0" ]
}

@test "masterscript with motionphoto2 present and no Live Photos still writes the ledger (exit 0)" {
  command -v motionphoto2 >/dev/null 2>&1 || skip "motionphoto2 not installed"
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/masterscript.sh" --skip-group "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/muxed-photo/library-ledger.tsv" ]
}

# --- exiftool stderr classification ----------------------------------------
# exiftool labels almost everything "Warning:", including real failures
# ("Warning: Error opening file"), so classification is by meaning, not prefix.

@test "a genuine failure is surfaced as a problem, despite its Warning: prefix" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  chmod 000 "$TMP/IMG_0001.JPG"            # exiftool cannot open it
  run "$DIR/rename_media.sh" "$TMP"
  chmod 644 "$TMP/IMG_0001.JPG" || true
  [ "$status" -eq 0 ]
  [[ "$output" == *"problem(s) encountered"* ]]
  [[ "$output" != *"No failures"* ]]
}

@test "a clean rename reports no errors and removes the empty error log" {
  printf 'x' > "$TMP/IMG_0001.JPG"          # renames via the FileModifyDate fallback
  run "$DIR/rename_media.sh" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No errors encountered"* ]]
  [ ! -f "$TMP/.workflow/rename_errors.log" ]
}

@test "masterscript preserves rename_errors.log into the results dir" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  chmod 000 "$TMP/IMG_0001.JPG"
  run "$DIR/masterscript.sh" --skip-mux --in-place --skip-group "$TMP"
  chmod 644 "$TMP/IMG_0001.JPG" || true
  [ "$status" -eq 0 ]
  # The run points the user at an error log, so it must outlive the cleanup - and
  # in-place is the harder branch: there TARGET/.workflow IS WORK_DIR.
  [ -f "$TMP/rename_errors.log" ]
  [ ! -d "$TMP/.workflow" ]
}

# A real (tiny) MP4. exiftool must parse the container to write the QuickTime/Keys date
# tags, so a stand-in of a few bytes will not do here.
MP4_B64='AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAAIZnJlZQAAAs1tZGF0AAACrgYF//+q3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2NSByMzIyMiBiMzU2MDVhIC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyNSAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTEgcmVmPTMgZGVibG9jaz0xOjA6MCBhbmFseXNlPTB4MzoweDExMyBtZT1oZXggc3VibWU9NyBwc3k9MSBwc3lfcmQ9MS4wMDowLjAwIG1peGVkX3JlZj0xIG1lX3JhbmdlPTE2IGNocm9tYV9tZT0xIHRyZWxsaXM9MSA4eDhkY3Q9MSBjcW09MCBkZWFkem9uZT0yMSwxMSBmYXN0X3Bza2lwPTEgY2hyb21hX3FwX29mZnNldD0tMiB0aHJlYWRzPTEgbG9va2FoZWFkX3RocmVhZHM9MSBzbGljZWRfdGhyZWFkcz0wIG5yPTAgZGVjaW1hdGU9MSBpbnRlcmxhY2VkPTAgYmx1cmF5X2NvbXBhdD0wIGNvbnN0cmFpbmVkX2ludHJhPTAgYmZyYW1lcz0zIGJfcHlyYW1pZD0yIGJfYWRhcHQ9MSBiX2JpYXM9MCBkaXJlY3Q9MSB3ZWlnaHRiPTEgb3Blbl9nb3A9MCB3ZWlnaHRwPTIga2V5aW50PTI1MCBrZXlpbnRfbWluPTI1IHNjZW5lY3V0PTQwIGludHJhX3JlZnJlc2g9MCByY19sb29rYWhlYWQ9NDAgcmM9Y3JmIG1idHJlZT0xIGNyZj0yMy4wIHFjb21wPTAuNjAgcXBtaW49MCBxcG1heD02OSBxcHN0ZXA9NCBpcF9yYXRpbz0xLjQwIGFxPTE6MS4wMACAAAAAD2WIhAAr//72c3wKa22xgQAAAxRtb292AAAAbG12aGQAAAAAAAAAAAAAAAAAAAPoAAAAKAABAAABAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACAAACP3RyYWsAAABcdGtoZAAAAAMAAAAAAAAAAAAAAAEAAAAAAAAAKAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAEAAAAAAEAAAABAAAAAAACRlZHRzAAAAHGVsc3QAAAAAAAAAAQAAACgAAAAAAAEAAAAAAbdtZGlhAAAAIG1kaGQAAAAAAAAAAAAAAAAAADIAAAACAFXEAAAAAAAtaGRscgAAAAAAAAAAdmlkZQAAAAAAAAAAAAAAAFZpZGVvSGFuZGxlcgAAAAFibWluZgAAABR2bWhkAAAAAQAAAAAAAAAAAAAAJGRpbmYAAAAcZHJlZgAAAAAAAAABAAAADHVybCAAAAABAAABInN0YmwAAAC+c3RzZAAAAAAAAAABAAAArmF2YzEAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAEAAQAEgAAABIAAAAAAAAAAEVTGF2YzYyLjExLjEwMCBsaWJ4MjY0AAAAAAAAAAAAAAAY//8AAAA0YXZjQwFkAAr/4QAXZ2QACqzZXsBEAAADAAQAAAMAyDxIllgBAAZo6+PLIsD9+PgAAAAAEHBhc3AAAAABAAAAAQAAABRidHJ0AAAAAAACKegAAAAAAAAAGHN0dHMAAAAAAAAAAQAAAAEAAAIAAAAAHHN0c2MAAAAAAAAAAQAAAAEAAAABAAAAAQAAABRzdHN6AAAAAAAAAsUAAAABAAAAFHN0Y28AAAAAAAAAAQAAADAAAABhdWR0YQAAAFltZXRhAAAAAAAAACFoZGxyAAAAAAAAAABtZGlyYXBwbAAAAAAAAAAAAAAAACxpbHN0AAAAJKl0b28AAAAcZGF0YQAAAAEAAAAATGF2ZjYyLjMuMTAw'

# A video with a QuickTime (UTC) date but NO Keys:CreationDate - the case that gets named
# in UTC and, before the check existed, said nothing about it.
make_utc_video() {
  printf '%s' "$MP4_B64" | base64 -d > "$1"
  exiftool -q -overwrite_original -QuickTime:CreateDate="2025:10:04 04:33:20" "$1"
}

# The same video WITH Keys:CreationDate - carries local time + offset, so it is named right.
make_local_video() {
  make_utc_video "$1"
  exiftool -q -overwrite_original -Keys:CreationDate="2025:10:04 12:33:20+08:00" "$1"
}

@test "a video named from a UTC tag is reported, not silently accepted" {
  make_utc_video "$TMP/clip.mp4"
  run "$DIR/rename_media.sh" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no Keys:CreationDate"* ]]
  [[ "$output" == *"offset from local time"* ]]
  [[ "$output" == *"20251004_043320.mp4"* ]]
}

@test "a video carrying Keys:CreationDate triggers no UTC note" {
  make_local_video "$TMP/clip.mp4"
  run "$DIR/rename_media.sh" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" != *"no Keys:CreationDate"* ]]
  # named from the local-time tag, not the UTC one
  [ -f "$TMP/20251004_123320.mp4" ]
}

@test "photos alone never trigger the UTC note" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/rename_media.sh" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" != *"no Keys:CreationDate"* ]]
}

@test "--dry-run reports the UTC case in the conditional, and renames nothing" {
  make_utc_video "$TMP/clip.mp4"
  run "$DIR/rename_media.sh" --dry-run "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WOULD be named from a UTC"* ]]
  [ -f "$TMP/clip.mp4" ]
}
