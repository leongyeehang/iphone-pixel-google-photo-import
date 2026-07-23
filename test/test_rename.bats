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
