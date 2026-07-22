#!/usr/bin/env bats
#
# Grouping logic: --size threshold, oversized-file warning, invalid size, and a
# real group -> ungroup round trip. Uses sparse files, so it costs no real disk and
# needs no external tools.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TMP="$(mktemp -d)"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# make_sparse <bytes> <path> — portable sparse file (macOS + Linux)
make_sparse() {
  dd if=/dev/null of="$2" bs=1 seek="$1" count=0 2>/dev/null
}

@test "an oversized file gets its own folder and a warning" {
  make_sparse $((8 * 1024 * 1024 * 1024))  "$TMP/20250101_120000.JPG"
  make_sparse $((20 * 1024 * 1024 * 1024)) "$TMP/20250102_120000.JPG"
  run "$DIR/group_files_size.sh" --dry-run "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"exceeds the"* ]]
  [[ "$output" == *"into 2 folder(s)"* ]]
}

@test "--size controls the grouping threshold" {
  make_sparse $((3 * 1024 * 1024 * 1024)) "$TMP/20250101_120000.JPG"
  make_sparse $((3 * 1024 * 1024 * 1024)) "$TMP/20250102_120000.JPG"

  run "$DIR/group_files_size.sh" --dry-run --size 5G "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"into 2 folder(s)"* ]]

  run "$DIR/group_files_size.sh" --dry-run --size 15G "$TMP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"into 1 folder(s)"* ]]
}

@test "invalid --size is rejected" {
  run "$DIR/group_files_size.sh" --size bogus "$TMP"
  [ "$status" -ne 0 ]
  [[ "$output" == *"invalid --size"* ]]
}

@test "group then ungroup round-trips the files" {
  make_sparse $((1024 * 1024)) "$TMP/20250101_120000.JPG"
  make_sparse $((1024 * 1024)) "$TMP/20250102_120000.JPG"

  run "$DIR/group_files_size.sh" --size 15G "$TMP"
  [ "$status" -eq 0 ]
  run bash -c "ls -d '$TMP'/*/ 2>/dev/null | wc -l | tr -d ' '"
  [ "$output" = "1" ]

  run "$DIR/ungroup.sh" "$TMP"
  [ "$status" -eq 0 ]
  [ -f "$TMP/20250101_120000.JPG" ]
  [ -f "$TMP/20250102_120000.JPG" ]
}

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
  run bash -c "ls -d '$TMP'/*/ | wc -l | tr -d ' '"
  [ "$output" = "1" ]
}

@test "group prints its shared version" {
  run "$DIR/group_files_size.sh" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"group_files_size.sh 1.1.0"* ]]
}
