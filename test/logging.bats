#!/usr/bin/env bats
# Tests for JSONL event logging (log_event_jsonl)

setup()    { load 'test_helper/common-setup'; _common_setup; }
teardown() { _common_teardown; }

# Helper: enable JSONL logging to a temp file
_enable_jsonl() {
  LOG_FORMAT="jsonl"
  LOG_FILE="${TEST_TMPDIR}/events.jsonl"
}

@test "log_event_jsonl: is a no-op when LOG_FORMAT is text" {
  LOG_FORMAT="text"
  LOG_FILE="${TEST_TMPDIR}/nope.jsonl"
  log_event_jsonl "test_event"
  [ ! -f "$LOG_FILE" ]
}

@test "log_event_jsonl: writes valid JSON" {
  _enable_jsonl
  log_event_jsonl "test_event"
  run jq -e . "$LOG_FILE"
  assert_success
}

@test "log_event_jsonl: includes schema_version field" {
  _enable_jsonl
  log_event_jsonl "test_event"
  run jq -r '.schema_version' "$LOG_FILE"
  assert_success
  assert_output "1"
}

@test "log_event_jsonl: includes run_id and engine fields" {
  _enable_jsonl
  RUN_ID="test-123"
  ENGINE="claude"
  log_event_jsonl "test_event"
  run jq -r '.run_id' "$LOG_FILE"
  assert_output "test-123"
  run jq -r '.engine' "$LOG_FILE"
  assert_output "claude"
}

@test "log_event_jsonl: includes worker_id when set" {
  _enable_jsonl
  WORKER_ID=3
  log_event_jsonl "test_event"
  run jq -r '.worker_id' "$LOG_FILE"
  assert_output "3"
}

@test "log_event_jsonl: omits worker_id when 0" {
  _enable_jsonl
  WORKER_ID=0
  log_event_jsonl "test_event"
  run jq -r '.worker_id // "absent"' "$LOG_FILE"
  assert_output "absent"
}

@test "log_event_jsonl: extra key/value pairs appear in output" {
  _enable_jsonl
  log_event_jsonl "iter_end" "status" "OK" "duration" "42"
  run jq -r '.status' "$LOG_FILE"
  assert_output "OK"
  run jq -r '.duration' "$LOG_FILE"
  assert_output "42"
}

@test "log_event_jsonl: numeric values are JSON numbers" {
  _enable_jsonl
  log_event_jsonl "test" "count" "99"
  run jq -e '.count == 99' "$LOG_FILE"
  assert_success
}

@test "log_event_jsonl: handles double quotes in values" {
  _enable_jsonl
  log_event_jsonl "test" "msg" 'He said "hello"'
  run jq -e . "$LOG_FILE"
  assert_success
  run jq -r '.msg' "$LOG_FILE"
  assert_output 'He said "hello"'
}

@test "log_event_jsonl: handles newlines in values" {
  _enable_jsonl
  log_event_jsonl "test" "msg" $'line1\nline2'
  run jq -e . "$LOG_FILE"
  assert_success
  run jq -r '.msg' "$LOG_FILE"
  assert_output $'line1\nline2'
}

@test "log_event_jsonl: handles backslashes in values" {
  _enable_jsonl
  log_event_jsonl "test" "path" 'C:\Users\foo'
  run jq -e . "$LOG_FILE"
  assert_success
  run jq -r '.path' "$LOG_FILE"
  assert_output 'C:\Users\foo'
}

@test "log_event_jsonl: handles tabs and control characters" {
  _enable_jsonl
  log_event_jsonl "test" "msg" $'col1\tcol2'
  run jq -e . "$LOG_FILE"
  assert_success
  run jq -r '.msg' "$LOG_FILE"
  assert_output $'col1\tcol2'
}

@test "log_event_jsonl: multiple events produce one JSON per line" {
  _enable_jsonl
  log_event_jsonl "event_a"
  log_event_jsonl "event_b"
  log_event_jsonl "event_c"
  local lines
  lines="$(wc -l < "$LOG_FILE" | tr -d ' ')"
  assert_equal "$lines" "3"
  # Each line is valid JSON
  while IFS= read -r line; do
    echo "$line" | jq -e . >/dev/null
  done < "$LOG_FILE"
}
