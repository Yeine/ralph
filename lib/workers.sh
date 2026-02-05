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
  local counters_file tmp_file
  counters_file="${WORKER_STATE_DIR}/w${wid}.counters"
  tmp_file="$(mktemp "${counters_file}.XXXXXX")" || { log_err "Failed to create temp counters file: $counters_file"; return 0; }
  if ! printf "COMPLETED=%s FAILED=%s ITERATIONS=%s\n" \
    "${COMPLETED_COUNT}" "${FAILED_COUNT}" "${ITERATION_COUNT}" > "$tmp_file"; then
    log_err "Failed to write counters file: $counters_file"
    rm -f "$tmp_file" 2>/dev/null || true
    return 0
  fi
  if ! mv "$tmp_file" "$counters_file"; then
    log_err "Failed to update counters file: $counters_file"
    rm -f "$tmp_file" 2>/dev/null || true
    return 0
  fi
}

read_all_counters() {
  local total_completed=0 total_failed=0 total_iterations=0
  [[ -n "${WORKER_STATE_DIR:-}" && -d "$WORKER_STATE_DIR" ]] || { echo "0 0 0"; return 0; }
  for f in "${WORKER_STATE_DIR}"/w*.counters; do
    [[ -f "$f" ]] || continue
    local line completed failed iterations
    line=""
    IFS= read -r line < "$f" 2>/dev/null || true
    if [[ "$line" =~ ^COMPLETED=([0-9]+)[[:space:]]+FAILED=([0-9]+)[[:space:]]+ITERATIONS=([0-9]+)$ ]]; then
      completed="${BASH_REMATCH[1]}"
      failed="${BASH_REMATCH[2]}"
      iterations="${BASH_REMATCH[3]}"
      total_completed=$((total_completed + completed))
      total_failed=$((total_failed + failed))
      total_iterations=$((total_iterations + iterations))
    fi
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
