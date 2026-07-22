#!/usr/bin/env bats
#
# CLI-surface tests: --help, --version, bad-path handling, unknown options.
# These need no external tools, so they run everywhere (incl. CI without exiftool).

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  SCRIPTS="masterscript run_mux_motionphoto rename_media group_files_size ungroup"
}

@test "every script prints usage on --help and exits 0" {
  for s in $SCRIPTS; do
    run "$DIR/$s.sh" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
  done
}

@test "every script prints its version on --version" {
  for s in $SCRIPTS; do
    run "$DIR/$s.sh" --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"$s.sh "* ]]
  done
}

@test "masterscript rejects a non-existent directory with a friendly error" {
  run "$DIR/masterscript.sh" /no/such/dir_xyz
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "group and ungroup also reject a non-existent directory" {
  run "$DIR/group_files_size.sh" /no/such/dir_xyz
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
  run "$DIR/ungroup.sh" /no/such/dir_xyz
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "masterscript rejects an unknown option" {
  run "$DIR/masterscript.sh" --definitely-not-an-option
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "run_mux warns and skips (exit 0) when motionphoto2 is absent" {
  command -v motionphoto2 >/dev/null 2>&1 && skip "motionphoto2 is installed"
  TMP="$(mktemp -d)"
  printf 'x' > "$TMP/IMG_0001.JPG"
  run "$DIR/run_mux_motionphoto.sh" "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"motionphoto2"* ]]
  rm -rf "$TMP"
}
