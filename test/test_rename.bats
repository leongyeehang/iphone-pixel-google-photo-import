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

@test "masterscript --skip-mux --skip-group renames in place" {
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/masterscript.sh" --skip-mux --skip-group "$TMP"
  [ "$status" -eq 0 ]
  [ ! -f "$TMP/IMG_0001.JPG" ]
  run bash -c "ls '$TMP'/2*.JPG"
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
