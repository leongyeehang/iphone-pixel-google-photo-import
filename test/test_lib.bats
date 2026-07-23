#!/usr/bin/env bats
#
# Unit tests for lib.sh: media identity + (Task 2) portable helpers.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  # shellcheck source=/dev/null
  source "$DIR/lib.sh"
}

@test "WORKFLOW_VERSION is set" {
  [ "$WORKFLOW_VERSION" = "1.1.0" ]
}

@test "is_media_file accepts images/videos (any case), rejects non-media" {
  run is_media_file "photo.JPG"; [ "$status" -eq 0 ]
  run is_media_file "shot.PNG";  [ "$status" -eq 0 ]
  run is_media_file "clip.mp4";  [ "$status" -eq 0 ]
  run is_media_file "movie.MTS"; [ "$status" -eq 0 ]
  run is_media_file "notes.txt"; [ "$status" -ne 0 ]
  run is_media_file "run.sh";    [ "$status" -ne 0 ]
  run is_media_file ".DS_Store"; [ "$status" -ne 0 ]
}

@test "is_image_file / is_video_file classify correctly" {
  run is_image_file "a.heic"; [ "$status" -eq 0 ]
  run is_image_file "a.mov";  [ "$status" -ne 0 ]
  run is_video_file "a.mov";  [ "$status" -eq 0 ]
  run is_video_file "a.jpg";  [ "$status" -ne 0 ]
}

@test "PHOTO_IMAGE_EXTS override narrows what counts as media" {
  PHOTO_IMAGE_EXTS="jpg"
  run is_media_file "shot.png"; [ "$status" -ne 0 ]
  run is_media_file "pic.jpg";  [ "$status" -eq 0 ]
}

@test "parse_size handles K/M/G suffixes and rejects bad input" {
  run parse_size "15G";  [ "$status" -eq 0 ]; [ "$output" = "16106127360" ]
  run parse_size "500M"; [ "$status" -eq 0 ]; [ "$output" = "524288000" ]
  run parse_size "2K";   [ "$status" -eq 0 ]; [ "$output" = "2048" ]
  run parse_size "1024"; [ "$status" -eq 0 ]; [ "$output" = "1024" ]
  run parse_size "bogus";[ "$status" -ne 0 ]
}

@test "epoch_from_filename_or_fs parses YYYYMMDD_HHMMSS" {
  run epoch_from_filename_or_fs "20250101_120000.JPG"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
}

@test "stat_size and dir_size_kb work on real files" {
  tmp="$(mktemp -d)"
  printf 'abcde' > "$tmp/f.jpg"
  run stat_size "$tmp/f.jpg"; [ "$status" -eq 0 ]; [ "$output" = "5" ]
  run dir_size_kb "$tmp";     [ "$status" -eq 0 ]; [[ "$output" =~ ^[0-9]+$ ]]
  run dir_size_kb "$tmp/nope";[ "$status" -eq 0 ]; [ "$output" = "0" ]
  rm -rf "$tmp"
}
