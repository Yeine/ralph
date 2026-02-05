#!/usr/bin/env bash
# shellcheck disable=SC2034  # Variables are used across sourced lib files
# loop.sh - Main loop, parallel worker, and parallel coordinator

# -----------------------------------------------------------------------------
# Sequential main loop
# -----------------------------------------------------------------------------
run_loop() {
  local prompt_file="$1"
  local iteration=1

  while true; do
    # BUG FIX #14: Use break instead of exit 0 - let caller handle cleanup
    if [[ $MAX_ITERATIONS -gt 0 && $iteration -gt $MAX_ITERATIONS ]]; then
      echo ""
      hr_green
      log_ok "${BOLD}Max iterations ($MAX_ITERATIONS) reached${NC}"
      hr_green
      set_title "RALPH LOOP | max iterations reached"
      break
    fi

    local rc=0
    run_iteration "$iteration" "$prompt_file" || rc=$?

    # BUG FIX #4: Handle special return codes from run_iteration
    if [[ "$rc" -eq 98 ]]; then
      # EXIT_SIGNAL with EXIT_ON_COMPLETE=true
      break
    fi

    echo ""
    log_dim "--- Iteration $iteration complete ---"
    [[ -n "${LOG_FILE:-}" ]] && echo "--- Iteration $iteration complete ---" >> "$LOG_FILE"

    iteration=$((iteration + 1))

    set_title "RALPH LOOP | idle (waiting)"
    if [[ "$QUIET" == "true" ]]; then
      log_info "Waiting $(fmt_hms "$WAIT_TIME")... (Ctrl+C to stop)"
      sleep "$WAIT_TIME"
    else
      wait_with_countdown "$WAIT_TIME"
    fi
  done

  show_run_summary
  bell end
}

# -----------------------------------------------------------------------------
# Parallel worker subprocess
# -----------------------------------------------------------------------------
run_worker() {
  local worker_id="$1"
  local prompt_file="$2"
  local log_file="${WORKER_STATE_DIR}/w${worker_id}.log"

  # Workers should not run the parent cleanup handler
  trap - EXIT INT TERM

  # Set worker identity
  WORKER_ID="$worker_id"

  # Redirect all output to worker log file
  exec > "$log_file" 2>&1

  # In multi-worker mode, separate log files per worker to avoid interleaving
  if [[ -n "${LOG_FILE:-}" ]]; then
    LOG_FILE="${LOG_FILE%.log}_w${worker_id}.log"
  fi

  # Disable features that don't make sense in worker subprocesses
  ENABLE_TITLE=false
  SHOW_RESOURCES=false
  WAIT_COUNTDOWN=false
  BELL_ON_COMPLETION=false
  BELL_ON_END=false

  # Ensure final counters are written on exit (covers normal exit, TERM, and INT)
  trap 'write_worker_counters "$WORKER_ID"' EXIT
  trap 'write_worker_counters "$WORKER_ID"; exit 143' TERM
  trap 'write_worker_counters "$WORKER_ID"; exit 130' INT

  local iteration=1

  while true; do
    # Check if another worker signaled all tasks complete
    if should_exit; then
      echo "[W${worker_id}] Exit sentinel detected, stopping."
      break
    fi

    if [[ $MAX_ITERATIONS -gt 0 && $iteration -gt $MAX_ITERATIONS ]]; then
      echo "[W${worker_id}] Max iterations (${MAX_ITERATIONS}) reached."
      break
    fi

    echo "[W${worker_id}] Starting iteration ${iteration}"
    local rc=0
    run_iteration "$iteration" "$prompt_file" || rc=$?

    # Write counters after each iteration
    write_worker_counters "$worker_id"

    # EXIT_SIGNAL detected (return code 99)
    if [[ $rc -eq 99 ]]; then
      echo "[W${worker_id}] EXIT_SIGNAL - all tasks complete."
      break
    fi

    iteration=$((iteration + 1))

    # Clear claim between iterations
    clear_claim "$worker_id"

    sleep "$WAIT_TIME"
  done

  echo "[W${worker_id}] Worker finished. Completed=${COMPLETED_COUNT} Failed=${FAILED_COUNT} Iterations=${ITERATION_COUNT}"
  write_worker_counters "$worker_id"
}

# -----------------------------------------------------------------------------
# Parallel coordinator
# -----------------------------------------------------------------------------
run_parallel() {
  local prompt_file="$1"

  setup_worker_state

  WORKER_PIDS=()
  TAIL_PIDS=()

  echo ""
  log_info "Spawning ${NUM_WORKERS} parallel workers..."
  echo ""

  # Spawn workers with staggered starts
  for i in $(seq 1 "$NUM_WORKERS"); do
    run_worker "$i" "$prompt_file" &
    WORKER_PIDS+=($!)
    log_ok "Worker W${i} started (PID ${WORKER_PIDS[${#WORKER_PIDS[@]}-1]})"
    # Stagger starts to reduce initial task collision
    if [[ "$i" -lt "$NUM_WORKERS" ]]; then
      sleep 2
    fi
  done

  echo ""
  log_info "All workers running. Streaming output..."
  hr

  # Color palette for worker prefixes
  local worker_colors=("$GREEN" "$CYAN" "$YELLOW" "$MAGENTA" "$BLUE" "$ORANGE"
                       "$GREEN" "$CYAN" "$YELLOW" "$MAGENTA" "$BLUE" "$ORANGE"
                       "$GREEN" "$CYAN" "$YELLOW" "$MAGENTA")

  # Start per-worker tail processes with colored prefixes
  for i in $(seq 1 "$NUM_WORKERS"); do
    local color="${worker_colors[$((i - 1))]}"
    local wlog="${WORKER_STATE_DIR}/w${i}.log"
    (
      tail -f "$wlog" 2>/dev/null | while IFS= read -r line; do
        printf "%b[W%d]%b %s\n" "$color" "$i" "$NC" "$line"
      done
    ) &
    TAIL_PIDS+=($!)
  done

  # Wait for all workers to finish
  local all_done=false
  while [[ "$all_done" == "false" ]]; do
    all_done=true
    for pid in "${WORKER_PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        all_done=false
        break
      fi
    done
    if [[ "$all_done" == "false" ]]; then
      sleep 2
    fi
  done

  # Stop tail processes
  for pid in "${TAIL_PIDS[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${TAIL_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done

  # Brief pause for any final log lines to flush
  sleep 1

  echo ""
  hr

  # Aggregate counters from all workers
  local totals
  totals="$(read_all_counters)"
  COMPLETED_COUNT="$(echo "$totals" | awk '{print $1}')"
  FAILED_COUNT="$(echo "$totals" | awk '{print $2}')"
  ITERATION_COUNT="$(echo "$totals" | awk '{print $3}')"

  show_run_summary
  bell end

  # Cleanup
  rm -rf "$WORKER_STATE_DIR" 2>/dev/null || true
}
