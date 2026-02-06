#!/usr/bin/env bats
# Tests for lib/workers.sh

setup()    { load 'test_helper/common-setup'; _common_setup; }
teardown() { _common_teardown; }

# --- setup_worker_state ---

@test "setup_worker_state: creates temp dir, claims file, exit sentinel, and counter files" {
  NUM_WORKERS=3
  setup_worker_state

  [[ -d "$WORKER_STATE_DIR" ]]
  assert_file_exist "$CLAIMS_FILE"
  assert_file_exist "${WORKER_STATE_DIR}/claims"
  assert_file_exist "${WORKER_STATE_DIR}/w1.counters"
  assert_file_exist "${WORKER_STATE_DIR}/w2.counters"
  assert_file_exist "${WORKER_STATE_DIR}/w3.counters"
  assert_file_exist "${WORKER_STATE_DIR}/w1.log"
  assert_file_exist "${WORKER_STATE_DIR}/w2.log"
  assert_file_exist "${WORKER_STATE_DIR}/w3.log"

  # Counter files should have initial values
  local content
  content="$(cat "${WORKER_STATE_DIR}/w1.counters")"
  assert_equal "$content" "COMPLETED=0 FAILED=0 ITERATIONS=0"

  # Clean up the created temp dir
  rm -rf "$WORKER_STATE_DIR"
}

# --- write_worker_counters ---

@test "write_worker_counters: writes counters to correct file" {
  WORKER_STATE_DIR="$TEST_TMPDIR"
  touch "${WORKER_STATE_DIR}/w1.counters"
  COMPLETED_COUNT=5
  FAILED_COUNT=2
  ITERATION_COUNT=7

  run write_worker_counters 1
  assert_success

  local content
  content="$(cat "${WORKER_STATE_DIR}/w1.counters")"
  assert_equal "$content" "COMPLETED=5 FAILED=2 ITERATIONS=7"
}

@test "write_worker_counters: is a no-op when WORKER_STATE_DIR is unset" {
  WORKER_STATE_DIR=""

  run write_worker_counters 1
  assert_success
  assert_output ""
}

# --- read_all_counters ---

@test "read_all_counters: returns 0 0 0 when WORKER_STATE_DIR is unset" {
  WORKER_STATE_DIR=""

  run read_all_counters
  assert_success
  assert_output "0 0 0"
}

@test "read_all_counters: sums counters from multiple worker files" {
  WORKER_STATE_DIR="$TEST_TMPDIR"
  echo "COMPLETED=3 FAILED=1 ITERATIONS=5" > "${WORKER_STATE_DIR}/w1.counters"
  echo "COMPLETED=2 FAILED=4 ITERATIONS=8" > "${WORKER_STATE_DIR}/w2.counters"

  run read_all_counters
  assert_success
  assert_output "5 5 13"
}

@test "read_all_counters: handles malformed counter files gracefully" {
  WORKER_STATE_DIR="$TEST_TMPDIR"
  echo "COMPLETED=3 FAILED=1 ITERATIONS=5" > "${WORKER_STATE_DIR}/w1.counters"
  echo "garbage data here" > "${WORKER_STATE_DIR}/w2.counters"
  echo "" > "${WORKER_STATE_DIR}/w3.counters"

  run read_all_counters
  assert_success
  # Only w1 is valid, w2 and w3 are skipped
  assert_output "3 1 5"
}

# --- signal_exit ---

@test "signal_exit: creates the EXIT_SENTINEL file" {
  EXIT_SENTINEL="${TEST_TMPDIR}/exit_signal"

  run signal_exit
  assert_success
  assert_file_exist "$EXIT_SENTINEL"
}

@test "signal_exit: is a no-op when EXIT_SENTINEL is unset" {
  EXIT_SENTINEL=""

  run signal_exit
  assert_success
}

# --- should_exit ---

@test "should_exit: returns true when sentinel file exists" {
  EXIT_SENTINEL="${TEST_TMPDIR}/exit_signal"
  touch "$EXIT_SENTINEL"

  run should_exit
  assert_success
}

@test "should_exit: returns false when sentinel file does not exist" {
  EXIT_SENTINEL="${TEST_TMPDIR}/exit_signal_nonexistent"

  run should_exit
  assert_failure
}
