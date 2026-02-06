#!/usr/bin/env bash
# common-setup.bash - Shared setup for all ralph bats tests

_common_setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  RALPH_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export RALPH_LIB_DIR="${RALPH_ROOT}/lib"
  export NO_COLOR=1  # Disable colors in tests

  # Source library modules in dependency order
  . "${RALPH_LIB_DIR}/colors.sh"
  setup_colors
  . "${RALPH_LIB_DIR}/utils.sh"
  . "${RALPH_LIB_DIR}/ui.sh"
  . "${RALPH_LIB_DIR}/lock.sh"
  . "${RALPH_LIB_DIR}/attempts.sh"
  . "${RALPH_LIB_DIR}/claims.sh"
  . "${RALPH_LIB_DIR}/workers.sh"

  # Create temp dir for test isolation
  TEST_TMPDIR="$(mktemp -d)"
  export TMPDIR="$TEST_TMPDIR"

  # Default global state needed by library functions
  export ATTEMPTS_FILE="${TEST_TMPDIR}/.ralph_attempts.json"
  export MAX_ATTEMPTS=3
  export ITERATION_TIMEOUT=600
  export ENGINE="claude"
  export STARTED_EPOCH="$(date '+%s')"
  export RUN_ID="test-run"
  export COMPLETED_COUNT=0
  export FAILED_COUNT=0
  export ITERATION_COUNT=0
}

_common_teardown() {
  [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}
