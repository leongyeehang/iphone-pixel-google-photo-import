#!/usr/bin/env bats
#
# verify_residue.sh - accounting for what Google Photos' "Free up space" left on the
# device. Needs exiftool; skipped automatically if absent.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  command -v exiftool >/dev/null 2>&1 || skip "exiftool not installed"
  TMP="$(mktemp -d)"
  BATCH="$TMP/260415-260503-9.8GB"
  RES="$TMP/leftovers"
  mkdir -p "$BATCH" "$RES"
  # Every test here classifies by the Motion Photo tag, so a build that cannot read it
  # would fail the whole file for the wrong reason. Skip loudly instead.
  make_motion "$TMP/.probe.jpg"
  [ "$(exiftool -q -q -s3 -XMP-GCamera:MotionPhoto "$TMP/.probe.jpg" 2>/dev/null)" = "1" ] \
    || skip "this exiftool cannot read XMP-GCamera:MotionPhoto"
  rm -f "$TMP/.probe.jpg"
}

teardown() {
  [ -n "${TMP:-}" ] && rm -rf "$TMP"
}

# Two real 1x1 JPEGs, embedded rather than generated. The Motion Photo one ALREADY carries
# XMP-GCamera:MotionPhoto, because older exiftool builds (Ubuntu CI ships one) can read that
# tag but refuse to write it - "Tag 'XMP-GCamera:MotionPhoto' is not defined". Baking it into
# the fixture keeps the suite portable. exiftool still has to parse the container, so the
# 1-byte stand-ins the rename tests use will not work here.
PLAIN_JPEG_B64='/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAQABAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A+mKKKK/Kz/QA/9k='
MOTION_JPEG_B64='/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAaADAAQAAAABAAAAAQAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/+ELHWh0dHA6Ly9ucy5hZG9iZS5jb20veGFwLzEuMC8APD94cGFja2V0IGJlZ2luPSfvu78nIGlkPSdXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQnPz4KPHg6eG1wbWV0YSB4bWxuczp4PSdhZG9iZTpuczptZXRhLycgeDp4bXB0az0nSW1hZ2U6OkV4aWZUb29sIDEzLjM2Jz4KPHJkZjpSREYgeG1sbnM6cmRmPSdodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjJz4KCiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0nJwogIHhtbG5zOkdDYW1lcmE9J2h0dHA6Ly9ucy5nb29nbGUuY29tL3Bob3Rvcy8xLjAvY2FtZXJhLyc+CiAgPEdDYW1lcmE6TW90aW9uUGhvdG8+MTwvR0NhbWVyYTpNb3Rpb25QaG90bz4KIDwvcmRmOkRlc2NyaXB0aW9uPgo8L3JkZjpSREY+CjwveDp4bXBtZXRhPgogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAogICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgCiAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAKICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgIAo8P3hwYWNrZXQgZW5kPSd3Jz8+/8AAEQgAAQABAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A+mKKKK/Kz/QA/9k='

make_plain()  { printf '%s' "$PLAIN_JPEG_B64"  | base64 -d > "$1"; }
make_motion() { printf '%s' "$MOTION_JPEG_B64" | base64 -d > "$1"; }

# Put a file in the Batch and leave an identical copy behind on the "device".
pushed_and_left() { "$1" "$BATCH/$2"; cp -p "$BATCH/$2" "$RES/$2"; }
# Put a file in the Batch that was reclaimed (no copy left behind).
pushed_only()     { "$1" "$BATCH/$2"; }

@test "verify_residue prints usage on --help and its version on --version" {
  run "$DIR/tools/verify_residue.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: verify_residue.sh"* ]]

  run "$DIR/tools/verify_residue.sh" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"verify_residue.sh"* ]]
}

@test "verify_residue fails clearly when an argument is missing" {
  run "$DIR/tools/verify_residue.sh" "$RES"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "verify_residue fails clearly on a missing directory" {
  run "$DIR/tools/verify_residue.sh" "$TMP/nope" "$BATCH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "verify_residue rejects an unknown option" {
  run "$DIR/tools/verify_residue.sh" --bogus "$RES" "$BATCH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown option"* ]]
}

@test "verify_residue fails when the Batch holds no media" {
  run "$DIR/tools/verify_residue.sh" "$RES" "$BATCH"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no media files"* ]]
}

@test "Motion Photos left behind are the expected outcome, not a failure" {
  pushed_and_left make_motion 20260415_101010.JPG
  pushed_and_left make_motion 20260415_101011.JPG
  pushed_only     make_plain  20260415_101012.JPG

  run "$DIR/tools/verify_residue.sh" "$RES" "$BATCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Expected behaviour"* ]]
  [[ "$output" == *"Safe to delete"* ]]
}

@test "the class table splits Motion Photos from plain files, with counts" {
  pushed_and_left make_motion 20260415_101010.JPG
  pushed_only     make_motion 20260415_101011.JPG
  pushed_only     make_plain  20260415_101012.JPG

  run "$DIR/tools/verify_residue.sh" "$RES" "$BATCH"
  [ "$status" -eq 0 ]
  # one of two Motion Photos left behind; the plain file was reclaimed
  [[ "$output" == *"JPEG Motion Photo"* ]]
  [[ "$output" == *"plain"* ]]
  [[ "$output" == *"Batch pushed:"* ]]
  [[ "$output" == *"Reclaimed:"* ]]
}

@test "a plain file left behind is flagged - the one pattern that suggests a real problem" {
  pushed_and_left make_motion 20260415_101010.JPG
  pushed_and_left make_plain  20260415_101012.JPG

  run "$DIR/tools/verify_residue.sh" "$RES" "$BATCH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ATTENTION"* ]]
  [[ "$output" == *"non-Motion-Photo"* ]]
}

@test "a leftover whose bytes differ from its master is reported" {
  pushed_and_left make_motion 20260415_101010.JPG
  printf 'tampered' >> "$RES/20260415_101010.JPG"

  run "$DIR/tools/verify_residue.sh" "$RES" "$BATCH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"DIFFERS: 20260415_101010.JPG"* ]]
  [[ "$output" == *"do not match their master"* ]]
}

@test "a leftover that is not in the Batch at all is reported" {
  pushed_only  make_motion 20260415_101010.JPG
  make_motion "$RES/20260415_999999.JPG"

  run "$DIR/tools/verify_residue.sh" "$RES" "$BATCH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"NOT IN BATCH: 20260415_999999.JPG"* ]]
}

@test "a fully reclaimed Batch reports nothing left behind" {
  pushed_only make_motion 20260415_101010.JPG
  pushed_only make_plain  20260415_101012.JPG

  run "$DIR/tools/verify_residue.sh" "$RES" "$BATCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"whole Batch was reclaimed"* ]]
}

@test "--no-hash skips the integrity check but still classifies" {
  pushed_and_left make_motion 20260415_101010.JPG
  printf 'tampered' >> "$RES/20260415_101010.JPG"

  run "$DIR/tools/verify_residue.sh" --no-hash "$RES" "$BATCH"
  [ "$status" -eq 0 ]
  [[ "$output" != *"identical"* ]]
  [[ "$output" == *"JPEG Motion Photo"* ]]
}

@test "non-media files and dotfiles are ignored on both sides" {
  pushed_and_left make_motion 20260415_101010.JPG
  printf 'x' > "$BATCH/library-ledger.tsv"
  printf 'x' > "$RES/.DS_Store"

  run "$DIR/tools/verify_residue.sh" "$RES" "$BATCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Batch pushed:"*"1 files"* ]]
  [[ "$output" == *"whole Batch was reclaimed"* || "$output" == *"Expected behaviour"* ]]
}
