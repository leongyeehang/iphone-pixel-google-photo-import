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
