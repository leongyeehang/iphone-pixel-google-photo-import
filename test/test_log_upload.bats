#!/usr/bin/env bats
#
# tools/log_upload.sh: appends a confirmed-upload row to upload-log.md.
# The script detects nothing about the backup itself — it only records what the
# operator has already verified — so these tests cover the recording contract.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LOGGER="$DIR/tools/log_upload.sh"
  TMP="$(mktemp -d)"
  BATCH="$TMP/lib/2026July28/muxed-photo/260415-260503-9.8GB"
  mkdir -p "$BATCH"
  for i in 1 2 3; do echo x > "$BATCH/2026041${i}_120000.HEIC"; done
  LOG="$TMP/lib/upload-log.md"
}

teardown() {
  rm -rf "$TMP"
}

@test "log_upload prints usage on --help and its version on --version" {
  run "$LOGGER" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]

  run "$LOGGER" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"log_upload.sh "* ]]
}

@test "log_upload appends a row with the batch, import folder and file count" {
  printf '| Batch | Import | Files | Pushed | Backup confirmed | Notes |\n|---|---|---|---|---|---|\n' > "$LOG"
  run "$LOGGER" --pushed 2026-08-29 --confirmed 2026-08-30 "$BATCH" "motion verified"
  [ "$status" -eq 0 ]

  line="$(tail -n 1 "$LOG")"
  [[ "$line" == *"260415-260503-9.8GB"* ]]   # batch name
  [[ "$line" == *"2026July28"* ]]            # import folder, two levels up
  [[ "$line" == *"| 3 |"* ]]                 # counted the files itself
  [[ "$line" == *"2026-08-29"* ]]
  [[ "$line" == *"2026-08-30"* ]]
  [[ "$line" == *"motion verified"* ]]
}

@test "notes are optional" {
  printf '| Batch |\n|---|\n' > "$LOG"
  run "$LOGGER" "$BATCH"
  [ "$status" -eq 0 ]
  [[ "$(tail -n 1 "$LOG")" == *"260415-260503-9.8GB"* ]]
}

@test "log_upload finds upload-log.md by walking up from the batch" {
  printf '| Batch |\n|---|\n' > "$LOG"
  run "$LOGGER" "$BATCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$LOG"* ]]
}

@test "log_upload creates the log when --log names a file that does not exist" {
  run "$LOGGER" --log "$TMP/fresh-log.md" "$BATCH"
  [ "$status" -eq 0 ]
  [ -f "$TMP/fresh-log.md" ]
  [[ "$(head -n 1 "$TMP/fresh-log.md")" == *"Batch"* ]]
}

@test "log_upload warns when the same batch is recorded twice" {
  printf '| Batch |\n|---|\n' > "$LOG"
  "$LOGGER" "$BATCH" >/dev/null
  run "$LOGGER" "$BATCH"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already recorded"* ]]
}

@test "log_upload warns when the directory is not a Batch folder" {
  printf '| Batch |\n|---|\n' > "$LOG"
  mkdir -p "$TMP/lib/2026July28/muxed-photo/not-a-batch"
  run "$LOGGER" "$TMP/lib/2026July28/muxed-photo/not-a-batch"
  [ "$status" -eq 0 ]
  [[ "$output" == *"does not look like a Batch folder"* ]]
}

@test "log_upload fails clearly on a missing directory" {
  run "$LOGGER" /no/such/batch_xyz
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "log_upload fails clearly when no log can be located" {
  run "$LOGGER" "$BATCH"    # no upload-log.md anywhere above it
  [ "$status" -eq 1 ]
  [[ "$output" == *"no upload-log.md found"* ]]
}
