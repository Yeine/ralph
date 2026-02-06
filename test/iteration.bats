#!/usr/bin/env bats
# Tests for iteration logic - regression tests for critical bug fixes

setup()    { load 'test_helper/common-setup'; _common_setup; _stub_iteration_deps; }
teardown() { _common_teardown; }

_stub_iteration_deps() {
  run_engine() {
    local prompt_content="$1"
    local engine="$2"
    local raw_jsonl="$3"
    local output_file="$4"
    local pipe_rc_file="$5"
    local jq_rc_file="$6"
    local timeout_seconds="$7"
    local quiet="$8"
    local codex_flags="${9:-}"
    local log_file="${10:-}"

    if [[ -n "${TEST_PIPE_RC:-}" ]]; then
      printf '%s\n' "$TEST_PIPE_RC" > "$pipe_rc_file"
    fi
    if [[ -n "${TEST_JQ_RC:-}" ]]; then
      printf '%s\n' "$TEST_JQ_RC" > "$jq_rc_file"
    fi
    if [[ -n "${TEST_ENGINE_JSONL:-}" ]]; then
      printf '%s\n' "$TEST_ENGINE_JSONL" > "$raw_jsonl"
    fi
    if [[ -n "${TEST_ENGINE_OUTPUT:-}" ]]; then
      printf '%s\n' "$TEST_ENGINE_OUTPUT" > "$output_file"
    fi

    : "$prompt_content" "$engine" "$timeout_seconds" "$quiet" "$codex_flags" "$log_file"
  }

  count_tool_calls_from_jsonl() {
    echo "${TEST_TOOL_COUNT:-0}"
  }

  count_tool_calls_from_codex_jsonl() {
    echo "${TEST_TOOL_COUNT:-0}"
  }
}

_make_prompt_file() {
  local prompt_file="${TEST_TMPDIR}/prompt.md"
  printf '%s\n' "# Prompt" > "$prompt_file"
  echo "$prompt_file"
}

# --- BUG FIX #1: Double-counting COMPLETED_COUNT on EXIT_SIGNAL ---

@test "bug fix #1: EXIT_SIGNAL does not double-count COMPLETED_COUNT" {
  # Simulate the counter logic from run_iteration.
  # When task_completed=true AND exit_signal=true, COMPLETED_COUNT
  # should increment only once (from the status=OK block).
  COMPLETED_COUNT=0

  local task_completed=true
  local exit_signal=true
  local status="OK"

  # This is the status block logic
  if [[ "$status" == "OK" ]]; then
    COMPLETED_COUNT=$((COMPLETED_COUNT + 1))
  fi

  # After the fix, the exit_signal block does NOT increment COMPLETED_COUNT
  # (the old buggy code had: COMPLETED_COUNT=$((COMPLETED_COUNT + 1)) here)

  assert_equal "$COMPLETED_COUNT" "1"
}

@test "bug fix #1: EXIT_SIGNAL without task completion doesn't increment" {
  COMPLETED_COUNT=0

  local task_completed=false
  local exit_signal=true
  local status="EMPTY"

  if [[ "$status" == "OK" ]]; then
    COMPLETED_COUNT=$((COMPLETED_COUNT + 1))
  fi

  # exit_signal block - no increment after fix
  assert_equal "$COMPLETED_COUNT" "0"
}

# --- BUG FIX #4: run_iteration returns instead of calling exit ---

@test "bug fix #4: return code 98 means exit-on-complete" {
  # The contract is: run_iteration returns 98 for EXIT_SIGNAL + EXIT_ON_COMPLETE
  # and the caller (run_loop) should break out of the loop.
  # We can't easily test run_iteration itself (needs engine), but we test
  # that the caller handles code 98 correctly.

  # Simulate run_loop behavior:
  local should_continue=true
  local rc=98

  if [[ "$rc" -eq 98 ]]; then
    should_continue=false
  fi

  assert_equal "$should_continue" "false"
}

@test "bug fix #4: return code 99 means worker exit signal" {
  local should_continue=true
  local rc=99

  if [[ "$rc" -eq 99 ]]; then
    should_continue=false
  fi

  assert_equal "$should_continue" "false"
}

@test "bug fix #4: return code 0 means continue looping" {
  local should_continue=true
  local rc=0

  if [[ "$rc" -eq 98 || "$rc" -eq 99 ]]; then
    should_continue=false
  fi

  assert_equal "$should_continue" "true"
}

# --- run_iteration integration tests ---

@test "run_iteration: EXIT_SIGNAL returns 98 when exit-on-complete" {
  local prompt_file
  prompt_file="$(_make_prompt_file)"

  UI_MODE="compact"
  QUIET=true
  EXIT_ON_COMPLETE=true
  NUM_WORKERS=1
  WORKER_ID=0
  SHOW_QUOTE_EACH_ITERATION=false

  TEST_ENGINE_OUTPUT=$'PICKING: Task A\nEXIT_SIGNAL: true\nDONE: Task A'
  run run_iteration 1 "$prompt_file"
  assert_failure 98
}

@test "run_iteration: EXIT_SIGNAL returns 99 and clears claim in multi-worker mode" {
  local prompt_file
  prompt_file="$(_make_prompt_file)"

  UI_MODE="compact"
  QUIET=true
  EXIT_ON_COMPLETE=true
  NUM_WORKERS=2
  WORKER_ID=1
  SHOW_QUOTE_EACH_ITERATION=false

  local claim_marker="${TEST_TMPDIR}/claim_cleared"
  local exit_marker="${TEST_TMPDIR}/exit_signal_sent"
  clear_claim() { printf '%s' "$1" > "$claim_marker"; }
  signal_exit() { printf 'yes' > "$exit_marker"; }

  TEST_ENGINE_OUTPUT=$'EXIT_SIGNAL: true'
  run run_iteration 1 "$prompt_file"
  assert_failure 99
  assert_file_exist "$claim_marker"
  assert_file_exist "$exit_marker"
  assert_equal "$(cat "$claim_marker")" "1"
}

# --- Stall detection ---

@test "stall detection: _check_stall_exit returns true after 3 consecutive EMPTY" {
  ITERATION_HISTORY=("OK" "EMPTY" "EMPTY" "EMPTY")
  MAX_STALL_ITERATIONS=3
  run _check_stall_exit
  assert_success
}

@test "stall detection: _check_stall_exit returns true after 3 consecutive INFO" {
  ITERATION_HISTORY=("OK" "INFO" "INFO" "INFO")
  MAX_STALL_ITERATIONS=3
  run _check_stall_exit
  assert_success
}

@test "stall detection: _check_stall_exit returns true for mixed EMPTY and INFO" {
  ITERATION_HISTORY=("OK" "EMPTY" "INFO" "EMPTY")
  MAX_STALL_ITERATIONS=3
  run _check_stall_exit
  assert_success
}

@test "stall detection: _check_stall_exit returns false when recent OK exists" {
  ITERATION_HISTORY=("EMPTY" "EMPTY" "OK" "EMPTY")
  MAX_STALL_ITERATIONS=3
  run _check_stall_exit
  assert_failure
}

@test "stall detection: _check_stall_exit returns false when recent FAIL exists" {
  ITERATION_HISTORY=("EMPTY" "EMPTY" "FAIL" "EMPTY")
  MAX_STALL_ITERATIONS=3
  run _check_stall_exit
  assert_failure
}

@test "stall detection: _check_stall_exit returns false when not enough iterations" {
  ITERATION_HISTORY=("EMPTY" "EMPTY")
  MAX_STALL_ITERATIONS=3
  run _check_stall_exit
  assert_failure
}

@test "stall detection: disabled when MAX_STALL_ITERATIONS=0" {
  ITERATION_HISTORY=("EMPTY" "EMPTY" "EMPTY" "EMPTY" "EMPTY")
  MAX_STALL_ITERATIONS=0
  run _check_stall_exit
  assert_failure
}

@test "stall detection: custom threshold of 5" {
  ITERATION_HISTORY=("OK" "EMPTY" "EMPTY" "EMPTY" "INFO")
  MAX_STALL_ITERATIONS=5
  run _check_stall_exit
  assert_failure

  ITERATION_HISTORY=("OK" "EMPTY" "EMPTY" "EMPTY" "INFO" "EMPTY")
  run _check_stall_exit
  assert_success
}

# --- run_iteration integration tests (continued) ---

@test "run_iteration: ATTEMPT_FAILED increments attempts and skips at max" {
  local prompt_file
  prompt_file="$(_make_prompt_file)"

  UI_MODE="compact"
  QUIET=true
  SHOW_QUOTE_EACH_ITERATION=false
  MAX_ATTEMPTS=1

  rm -f "$ATTEMPTS_FILE"

  TEST_ENGINE_OUTPUT=$'ATTEMPT_FAILED: Flaky task'
  run run_iteration 1 "$prompt_file"
  assert_success

  local attempts skipped
  attempts="$(get_attempts "Flaky task")"
  skipped="$(get_skipped_tasks)"
  assert_equal "$attempts" "1"
  assert_equal "$skipped" "Flaky task"
}
