#!/usr/bin/env bash
# common-setup.bash - Shared setup for all ralph bats tests

_common_setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  RALPH_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export RALPH_LIB_DIR="${RALPH_ROOT}/lib"
  export NO_COLOR=1  # Disable colors in tests

  # Source library modules in dependency order (match bin/ralph)
  . "${RALPH_LIB_DIR}/colors.sh"
  . "${RALPH_LIB_DIR}/utils.sh"
  . "${RALPH_LIB_DIR}/ui.sh"
  . "${RALPH_LIB_DIR}/lock.sh"
  . "${RALPH_LIB_DIR}/attempts.sh"
  . "${RALPH_LIB_DIR}/claims.sh"
  . "${RALPH_LIB_DIR}/workers.sh"
  . "${RALPH_LIB_DIR}/engine.sh"
  . "${RALPH_LIB_DIR}/iteration.sh"
  . "${RALPH_LIB_DIR}/loop.sh"

  setup_colors

  # Create temp dir for test isolation
  TEST_TMPDIR="$(mktemp -d)"
  export TMPDIR="$TEST_TMPDIR"

  # Default global state needed by library functions
  export PROMPT_FILE="RALPH_TASK.md"
  export MAX_ITERATIONS=0
  export WAIT_TIME=5
  export USE_CAFFEINATE=false
  export LOG_FILE=""
  export ATTEMPTS_FILE="${TEST_TMPDIR}/.ralph_attempts.json"
  export MAX_ATTEMPTS=3
  export ITERATION_TIMEOUT=600
  export MAX_TOOL_CALLS=50
  export QUIET=false
  export ENGINE="claude"
  export CODEX_EXEC_FLAGS="--full-auto"
  export SHOW_QUOTE_EACH_ITERATION=true
  export BELL_ON_COMPLETION=false
  export BELL_ON_END=false
  export EXIT_ON_COMPLETE=true
  export ENABLE_TITLE=true
  export SHOW_RESOURCES=true
  export WAIT_COUNTDOWN=true
  export ALLOWED_TOOLS=""
  export DISALLOWED_TOOLS=""
  export NUM_WORKERS=1
  export WORKER_ID=0
  export UI_MODE="full"
  export SHOW_LOGO=true
  export SHOW_STATUS_LINE=true
  export UI_ASCII=false
  export STARTED_EPOCH="$(date '+%s')"
  export RUN_ID="test-run"
  export COMPLETED_COUNT=0
  export FAILED_COUNT=0
  export ITERATION_COUNT=0

  setup_ui_charset
}

_common_teardown() {
  [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}
