#!/usr/bin/env bats
# Integration tests - end-to-end smoke tests for the ralph CLI

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  RALPH_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_TMPDIR="$(mktemp -d)"
  export NO_COLOR=1
  export ATTEMPTS_FILE="${TEST_TMPDIR}/.ralph_attempts.json"
}
teardown() {
  [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

# --- --help ---

@test "ralph --help: exits 0 and shows usage" {
  run "${RALPH_ROOT}/bin/ralph" --help
  assert_success
  assert_output --partial "Ralph Loop"
  assert_output --partial "--prompt"
  assert_output --partial "--engine"
  assert_output --partial "--workers"
}

# --- --show-attempts ---

@test "ralph --show-attempts: works with no prior state" {
  run "${RALPH_ROOT}/bin/ralph" --show-attempts
  assert_success
  assert_output --partial "No attempts tracked"
}

# --- --clear-attempts ---

@test "ralph --clear-attempts: resets file" {
  # ralph uses .ralph_attempts.json in CWD by default, so run from tmpdir
  echo '{"k":{"task":"old task","attempts":3,"skipped":false}}' > "${TEST_TMPDIR}/.ralph_attempts.json"
  run bash -c "cd '${TEST_TMPDIR}' && '${RALPH_ROOT}/bin/ralph' --clear-attempts"
  assert_success
  assert_output --partial "Cleared"
  run cat "${TEST_TMPDIR}/.ralph_attempts.json"
  assert_output "{}"
}

# --- missing prompt file ---

@test "ralph: exits with error when prompt file missing" {
  run "${RALPH_ROOT}/bin/ralph" --prompt "${TEST_TMPDIR}/nonexistent-file.md"
  assert_failure
  assert_output --partial "not found"
}

# --- invalid engine ---

@test "ralph: exits with error for unknown engine" {
  run "${RALPH_ROOT}/bin/ralph" --engine "gpt4"
  assert_failure
  assert_output --partial "Unknown engine"
}

# --- invalid workers ---

@test "ralph: exits with error for invalid workers count" {
  run "${RALPH_ROOT}/bin/ralph" --workers 0
  assert_failure
  assert_output --partial "Workers must be 1-16"
}

@test "ralph: exits with error for workers > 16" {
  run "${RALPH_ROOT}/bin/ralph" --workers 20
  assert_failure
  assert_output --partial "Workers must be 1-16"
}

# --- unknown option ---

@test "ralph: exits with error for unknown option" {
  run "${RALPH_ROOT}/bin/ralph" --foobar
  assert_failure
  assert_output --partial "Unknown option"
}
