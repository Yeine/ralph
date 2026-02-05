#!/usr/bin/env bats
# Tests for lib/attempts.sh

setup() {
  load 'test_helper/common-setup'; _common_setup
  init_attempts_file
}
teardown() { _common_teardown; }

# --- init_attempts_file ---

@test "init: creates empty JSON object" {
  assert_file_exists "$ATTEMPTS_FILE"
  run cat "$ATTEMPTS_FILE"
  assert_output "{}"
}

@test "init: is idempotent (doesn't overwrite existing)" {
  increment_attempts "task 1" >/dev/null
  init_attempts_file
  run get_attempts "task 1"
  assert_output "1"
}

# --- get_attempts ---

@test "get_attempts: returns 0 for unknown task" {
  run get_attempts "unknown task"
  assert_output "0"
}

@test "get_attempts: returns correct count after increments" {
  increment_attempts "fix bug" >/dev/null
  increment_attempts "fix bug" >/dev/null
  run get_attempts "fix bug"
  assert_output "2"
}

@test "get_attempts: treats non-numeric attempts as 0" {
  local key
  key="$(task_hash "weird task")"
  printf '{"%s":{"task":"weird task","attempts":"oops","skipped":false}}\n' "$key" > "$ATTEMPTS_FILE"
  run get_attempts "weird task"
  assert_output "0"
}

@test "get_attempts: returns 0 when attempts file is corrupted" {
  printf '{not json' > "$ATTEMPTS_FILE"
  run get_attempts "broken task"
  assert_success
  assert_output "0"
}

# --- increment_attempts ---

@test "increment_attempts: increases count and returns new value" {
  run increment_attempts "fix bug"
  assert_output "1"
  run increment_attempts "fix bug"
  assert_output "2"
  run increment_attempts "fix bug"
  assert_output "3"
}

@test "increment_attempts: tracks multiple tasks independently" {
  increment_attempts "task A" >/dev/null
  increment_attempts "task A" >/dev/null
  increment_attempts "task B" >/dev/null

  run get_attempts "task A"
  assert_output "2"
  run get_attempts "task B"
  assert_output "1"
}

# --- mark_skipped ---

@test "mark_skipped: sets skipped flag" {
  increment_attempts "fix bug" >/dev/null
  mark_skipped "fix bug"
  run get_skipped_tasks
  assert_output --partial "fix bug"
}

@test "mark_skipped: works even without prior increment" {
  mark_skipped "brand new task"
  run get_skipped_tasks
  assert_output --partial "brand new task"
}

# --- get_skipped_tasks ---

@test "get_skipped_tasks: returns empty when none skipped" {
  run get_skipped_tasks
  assert_output ""
}

@test "get_skipped_tasks: returns all skipped tasks" {
  mark_skipped "task 1"
  mark_skipped "task 2"
  run get_skipped_tasks
  assert_output --partial "task 1"
  assert_output --partial "task 2"
}

@test "get_skipped_tasks: excludes non-skipped tasks" {
  increment_attempts "not skipped" >/dev/null
  mark_skipped "is skipped"
  run get_skipped_tasks
  assert_output "is skipped"
  refute_output --partial "not skipped"
}

@test "get_skipped_tasks: returns empty when attempts file is corrupted" {
  printf '{not json' > "$ATTEMPTS_FILE"
  run get_skipped_tasks
  assert_success
  assert_output ""
}

# --- clear_attempts ---

@test "clear_attempts: resets all state" {
  increment_attempts "task 1" >/dev/null
  increment_attempts "task 2" >/dev/null
  mark_skipped "task 2"
  clear_attempts

  run get_attempts "task 1"
  assert_output "0"
  run get_attempts "task 2"
  assert_output "0"
  run get_skipped_tasks
  assert_output ""
}

# --- show_attempts ---

@test "show_attempts: prints empty state when no attempts" {
  run show_attempts
  assert_output --partial "Current attempt tracking state"
  assert_output --partial "No attempts tracked yet."
}

@test "show_attempts: prints empty state when attempts file is empty" {
  : > "$ATTEMPTS_FILE"
  run show_attempts
  assert_success
  assert_output --partial "No attempts tracked yet."
}

@test "show_attempts: reports parse failure for corrupted attempts file" {
  printf '{not json' > "$ATTEMPTS_FILE"
  run show_attempts
  assert_failure
  assert_output --partial "Failed to parse attempts file"
}

@test "show_attempts: lists attempts and skipped tasks" {
  increment_attempts "task A" >/dev/null
  increment_attempts "task A" >/dev/null
  mark_skipped "task B"
  run show_attempts
  assert_output --partial "task A: 2 attempts"
  assert_output --partial "task B: SKIPPED (attempts=0)"
}
