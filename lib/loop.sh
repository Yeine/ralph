#!/usr/bin/env bash
# shellcheck disable=SC2034  # Variables are used across sourced lib files
# loop.sh - Main loop, parallel worker, and parallel coordinator

# -----------------------------------------------------------------------------
# Stall detection helper
# -----------------------------------------------------------------------------
# Check if the last N iterations were all non-productive (EMPTY or INFO).
# Returns 0 (true) if stalled, 1 (false) otherwise.
_check_stall_exit() {
  local max_stall="${MAX_STALL_ITERATIONS:-3}"
  [[ $max_stall -gt 0 ]] || return 1
  local history_len=${#ITERATION_HISTORY[@]}
  [[ $history_len -ge $max_stall ]] || return 1

  local i status
  for ((i = history_len - max_stall; i < history_len; i++)); do
    status="${ITERATION_HISTORY[$i]}"
    if [[ $status == "OK" || $status == "FAIL" ]]; then
      return 1
    fi
  done
  return 0
}

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
      set_smart_title "done" "" "$COMPLETED_COUNT" "$FAILED_COUNT" ""
      break
    fi

    local rc=0
    run_iteration "$iteration" "$prompt_file" || rc=$?

    # BUG FIX #4: Handle special return codes from run_iteration
    if [[ $rc -eq 98 ]]; then
      # EXIT_SIGNAL with EXIT_ON_COMPLETE=true
      break
    fi

    # Stall detection: auto-exit after N consecutive non-productive iterations
    if _check_stall_exit; then
      echo ""
      hr_green
      log_ok "${BOLD}Stall detected: ${MAX_STALL_ITERATIONS} consecutive non-productive iterations${NC}"
      log_ok "${BOLD}All tasks may be complete (agent did not emit EXIT_SIGNAL)${NC}"
      hr_green
      set_smart_title "done" "" "$COMPLETED_COUNT" "$FAILED_COUNT" ""
      log_event_jsonl "stall_exit" \
        "consecutive" "$MAX_STALL_ITERATIONS" \
        "iteration" "$iteration"
      break
    fi

    if [[ ${UI_MODE:-full} == "full" ]]; then
      echo ""
      log_dim "--- Iteration $iteration complete ---"
      [[ -n ${LOG_FILE:-} && ${LOG_FORMAT:-text} == "text" ]] && echo "--- Iteration $iteration complete ---" >>"$LOG_FILE"
    fi

    iteration=$((iteration + 1))

    set_smart_title "idle" "" "$COMPLETED_COUNT" "$FAILED_COUNT" ""

    # Wait between iterations (with keyboard shortcuts)
    if [[ ${UI_MODE:-full} == "dashboard" ]]; then
      dashboard_countdown "$WAIT_TIME"
    elif [[ ${UI_MODE:-full} == "full" ]]; then
      if [[ $QUIET == "true" ]]; then
        log_info "Waiting $(fmt_hms "$WAIT_TIME")... (Ctrl+C to stop)"
        sleep "$WAIT_TIME"
      else
        wait_with_countdown "$WAIT_TIME"
      fi
    else
      sleep "$WAIT_TIME"
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
  exec >"$log_file" 2>&1

  # In multi-worker mode, separate log files per worker to avoid interleaving
  if [[ -n ${LOG_FILE:-} ]]; then
    LOG_FILE="${LOG_FILE%.log}_w${worker_id}.log"
    : >"$LOG_FILE" # create early so file exists even if no iterations run
  fi

  # Disable features that don't make sense in worker subprocesses
  ENABLE_TITLE=false
  SHOW_RESOURCES=false
  WAIT_COUNTDOWN=false
  BELL_ON_COMPLETION=false
  BELL_ON_END=false
  ENABLE_NOTIFY=false

  # Ensure final counters are written on exit (covers normal exit, TERM, and INT)
  trap 'write_worker_counters "$WORKER_ID"' EXIT
  trap 'write_worker_counters "$WORKER_ID"; exit 143' TERM
  trap 'write_worker_counters "$WORKER_ID"; exit 130' INT

  local iteration=1

  while true; do
    # Check if another worker signaled all tasks complete
    if should_exit; then
      printf '%s\n' "[W${worker_id}] Exit sentinel detected, stopping."
      break
    fi

    if [[ $MAX_ITERATIONS -gt 0 && $iteration -gt $MAX_ITERATIONS ]]; then
      printf '%s\n' "[W${worker_id}] Max iterations (${MAX_ITERATIONS}) reached."
      break
    fi

    printf '%s\n' "[W${worker_id}] Starting iteration ${iteration}"
    local rc=0
    run_iteration "$iteration" "$prompt_file" || rc=$?

    # Write counters after each iteration
    write_worker_counters "$worker_id"

    # EXIT_SIGNAL detected (return code 99)
    if [[ $rc -eq 99 ]]; then
      printf '%s\n' "[W${worker_id}] EXIT_SIGNAL - all tasks complete."
      break
    fi

    # Stall detection: auto-exit after N consecutive non-productive iterations
    if _check_stall_exit; then
      printf '%s\n' "[W${worker_id}] Stall detected: ${MAX_STALL_ITERATIONS} consecutive non-productive iterations."
      log_event_jsonl "stall_exit" \
        "consecutive" "$MAX_STALL_ITERATIONS" \
        "iteration" "$iteration" \
        "worker_id" "$worker_id"
      signal_exit
      clear_claim "$worker_id"
      break
    fi

    iteration=$((iteration + 1))

    # Clear claim between iterations
    clear_claim "$worker_id"

    sleep "$WAIT_TIME"
  done

  printf '%s\n' "[W${worker_id}] Worker finished. Completed=${COMPLETED_COUNT} Failed=${FAILED_COUNT} Iterations=${ITERATION_COUNT}"
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

  if [[ ${UI_MODE:-full} != "minimal" ]]; then
    echo ""
    log_info "Spawning ${NUM_WORKERS} parallel workers..."
    echo ""
  fi

  # Spawn workers with staggered starts
  for i in $(seq 1 "$NUM_WORKERS"); do
    run_worker "$i" "$prompt_file" &
    WORKER_PIDS+=($!)
    if [[ ${UI_MODE:-full} != "minimal" ]]; then
      log_ok "Worker W${i} started (PID ${WORKER_PIDS[${#WORKER_PIDS[@]} - 1]})"
    fi
    # Stagger starts to reduce initial task collision
    if [[ $i -lt $NUM_WORKERS ]]; then
      sleep 5
    fi
  done

  if [[ ${UI_MODE:-full} != "minimal" ]]; then
    echo ""
    log_info "All workers running. Streaming output..."
    hr
  fi

  # Dashboard mode: render dashboard instead of tailing logs
  if [[ ${UI_MODE:-full} == "dashboard" ]]; then
    _run_parallel_dashboard
  else
    _run_parallel_tailed "$prompt_file"
  fi

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

# Parallel mode with tailed worker logs (default)
_run_parallel_tailed() {
  # Color palette for worker prefixes
  local worker_colors=("$GREEN" "$CYAN" "$YELLOW" "$MAGENTA" "$BLUE" "$ORANGE"
    "$GREEN" "$CYAN" "$YELLOW" "$MAGENTA" "$BLUE" "$ORANGE"
    "$GREEN" "$CYAN" "$YELLOW" "$MAGENTA")

  # Start per-worker tail processes with colored prefixes
  if [[ ${UI_MODE:-full} != "minimal" ]]; then
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
  fi

  # Wait for all workers to finish
  local all_done=false
  while [[ $all_done == "false" ]]; do
    all_done=true
    for pid in "${WORKER_PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        all_done=false
        break
      fi
    done
    if [[ $all_done == "false" ]]; then
      sleep 2
    fi
  done

  # Stop tail processes and their pipeline children (tail -f survives plain kill)
  for pid in ${TAIL_PIDS[@]+"${TAIL_PIDS[@]}"}; do
    _kill_tree "$pid"
  done
  for pid in ${TAIL_PIDS[@]+"${TAIL_PIDS[@]}"}; do
    wait "$pid" 2>/dev/null || true
  done

  sleep 1

  if [[ ${UI_MODE:-full} != "minimal" ]]; then
    echo ""
    hr
  fi
}

# Parallel mode with dashboard rendering
_run_parallel_dashboard() {
  local all_done=false
  while [[ $all_done == "false" ]]; do
    all_done=true
    for pid in "${WORKER_PIDS[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        all_done=false
        break
      fi
    done

    if [[ $all_done == "false" ]]; then
      # Aggregate live counters for display
      local totals
      totals="$(read_all_counters)"
      local dash_completed dash_failed dash_iterations
      dash_completed="$(echo "$totals" | awk '{print $1}')"
      dash_failed="$(echo "$totals" | awk '{print $2}')"
      dash_iterations="$(echo "$totals" | awk '{print $3}')"

      local skipped_now run_elapsed
      skipped_now="$(get_skipped_tasks 2>/dev/null | wc -l | tr -d ' ')"
      run_elapsed=$(($(date '+%s') - STARTED_EPOCH))

      write_dashboard_state "$dash_iterations" "RUNNING" "" \
        "$dash_completed" "$dash_failed" "$skipped_now" \
        "0" "$ITERATION_TIMEOUT" "0" "$MAX_TOOL_CALLS" "" "$run_elapsed"
      render_dashboard "" "" 0

      sleep 2
    fi
  done

  # Wait for workers to actually finish
  for pid in "${WORKER_PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
}
