#!/usr/bin/env bash
# shellcheck disable=SC2034  # Variables are used across sourced lib files
# workers.sh - Worker state management for parallel mode

# Global state (set in setup_worker_state)
WORKER_STATE_DIR="${WORKER_STATE_DIR:-}"
EXIT_SENTINEL="${EXIT_SENTINEL:-}"

setup_worker_state() {
  WORKER_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ralph_workers.XXXXXX")"
  CLAIMS_FILE="${WORKER_STATE_DIR}/claims"
  CLAIMS_LOCK="${WORKER_STATE_DIR}/claims.lck"
  EXIT_SENTINEL="${WORKER_STATE_DIR}/exit_signal"
  touch "$CLAIMS_FILE"
  for i in $(seq 1 "$NUM_WORKERS"); do
    touch "${WORKER_STATE_DIR}/w${i}.log"
    echo "COMPLETED=0 FAILED=0 ITERATIONS=0" > "${WORKER_STATE_DIR}/w${i}.counters"
  done
}

write_worker_counters() {
  local wid="$1"
  [[ -z "${WORKER_STATE_DIR:-}" ]] && return 0
  echo "COMPLETED=${COMPLETED_COUNT} FAILED=${FAILED_COUNT} ITERATIONS=${ITERATION_COUNT}" \
    > "${WORKER_STATE_DIR}/w${wid}.counters"
}

read_all_counters() {
  local total_completed=0 total_failed=0 total_iterations=0
  for f in "${WORKER_STATE_DIR}"/w*.counters; do
    [[ -f "$f" ]] || continue
    local completed failed iterations
    completed="$(sed -n 's/.*COMPLETED=\([0-9]*\).*/\1/p' "$f" 2>/dev/null)"
    failed="$(sed -n 's/.*FAILED=\([0-9]*\).*/\1/p' "$f" 2>/dev/null)"
    iterations="$(sed -n 's/.*ITERATIONS=\([0-9]*\).*/\1/p' "$f" 2>/dev/null)"
    total_completed=$((total_completed + ${completed:-0}))
    total_failed=$((total_failed + ${failed:-0}))
    total_iterations=$((total_iterations + ${iterations:-0}))
  done
  echo "$total_completed $total_failed $total_iterations"
}

signal_exit() {
  [[ -z "${EXIT_SENTINEL:-}" ]] && return 0
  touch "$EXIT_SENTINEL"
}

should_exit() {
  [[ -n "${EXIT_SENTINEL:-}" && -f "$EXIT_SENTINEL" ]]
}
