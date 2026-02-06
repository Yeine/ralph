#!/usr/bin/env bash
# shellcheck disable=SC2001  # sed used for multiline prefix insertion
# iteration.sh - Core iteration logic
#
# Return codes:
#   0  - Normal completion (continue looping)
#   98 - EXIT_SIGNAL with EXIT_ON_COMPLETE=true (caller should exit cleanly)
#   99 - EXIT_SIGNAL in multi-worker mode (worker should stop)

run_iteration() {
  local iteration="$1"
  local prompt_file="$2"

  local iter_started_epoch iter_started_ts
  iter_started_epoch="$(date '+%s')"
  iter_started_ts="$(date '+%Y-%m-%d %H:%M:%S')"

  local iter_quote=""
  if [[ "${SHOW_QUOTE_EACH_ITERATION:-true}" == "true" && "${UI_MODE:-full}" != "minimal" ]]; then
    iter_quote="$(pick_ralph_quote)"
  fi

  # Get current stats
  local skipped_count
  skipped_count="$(get_skipped_tasks | wc -l | tr -d ' ')"

  local time_short
  time_short="$(date '+%H:%M:%S')"

  local run_elapsed
  run_elapsed=$(( iter_started_epoch - STARTED_EPOCH ))

  set_smart_title "running" "$iteration" "$COMPLETED_COUNT" "$FAILED_COUNT" ""

  local quiet_for_engine="$QUIET"
  if [[ "${UI_MODE:-full}" != "full" ]]; then
    quiet_for_engine=true
  fi

  # Write dashboard state before engine launch
  if [[ "${UI_MODE:-full}" == "dashboard" ]]; then
    write_dashboard_state "$iteration" "RUNNING" "" \
      "$COMPLETED_COUNT" "$FAILED_COUNT" "$skipped_count" \
      0 "$ITERATION_TIMEOUT" 0 "$MAX_TOOL_CALLS" "$iter_quote" "$run_elapsed"
    render_dashboard "" "" 0
  fi

  # Print iteration start banner (normal output, no cursor tricks)
  if [[ "${UI_MODE:-full}" == "full" ]]; then
    echo ""
    render_dynamic_banner "$iteration" "$time_short" "$iter_quote" "RUNNING" \
      "$COMPLETED_COUNT" "$FAILED_COUNT" "$skipped_count" \
      0 "$ITERATION_TIMEOUT" 0 "$MAX_TOOL_CALLS" "" "" "$run_elapsed"
    if [[ "$QUIET" == "false" ]]; then
      show_resources
    fi
    echo ""
  fi

  local state_before state_after files_changed
  state_before="$(get_file_state_hash)"
  files_changed=false

  [[ -n "${LOG_FILE:-}" && "${LOG_FORMAT:-text}" == "text" ]] && printf "=== ITERATION %s - %s (run %s) ===\n" "$iteration" "$iter_started_ts" "$RUN_ID" >> "$LOG_FILE"

  # JSONL event: iteration_start
  log_event_jsonl "iteration_start" \
    "iteration" "$iteration" \
    "run_id" "$RUN_ID"

  local prompt_content
  prompt_content="$(cat "$prompt_file")"

  local skipped_tasks skipped_list
  skipped_tasks="$(get_skipped_tasks || true)"
  if [[ -n "$skipped_tasks" ]]; then
    skipped_list="$(printf '%s\n' "$skipped_tasks" | sed 's/^/- /')"
    prompt_content="${prompt_content}

---
**SKIPPED TASKS (do not attempt these - they have failed ${MAX_ATTEMPTS}+ times):**
${skipped_list}

If the first unchecked item matches any skipped task, move to the next unchecked item.
---"
  fi

  # Parallel worker coordination: offset + claims
  if [[ "$NUM_WORKERS" -gt 1 && "$WORKER_ID" -gt 0 ]]; then
    local other_claims
    other_claims="$(get_other_claims "$WORKER_ID")"
    local claims_list="" claims_block
    if [[ -n "$other_claims" ]]; then
      claims_list="$(printf '%s\n' "$other_claims" | sed 's/^/- /')"
      claims_block="Tasks currently in progress by other workers (DO NOT pick these):
${claims_list}"
    else
      claims_block="(No other workers have active tasks right now)"
    fi
    prompt_content="${prompt_content}

---
**PARALLEL WORKER COORDINATION**
You are worker ${WORKER_ID} of ${NUM_WORKERS} running in parallel.
To avoid duplicate work with other parallel workers:
1. Skip any tasks listed below that are currently being worked on by other workers
2. From the remaining unchecked items, pick item #${WORKER_ID} (counting from the top)
3. If fewer remaining unchecked items than your worker number, pick the last unchecked one

IMPORTANT: Other workers are writing to the same output/state files concurrently.
If you see entries or changes you didn't make, that is NORMAL - another worker wrote them.
Do NOT ask about it. Just continue with YOUR assigned task and append your own results.

${claims_block}
---"
  fi

  # Create temp files for this iteration
  local output_file raw_jsonl pipe_rc_file jq_rc_file
  output_file="$(mktemp "${TMPDIR:-/tmp}/ralph_out.XXXXXX")"
  raw_jsonl="$(mktemp "${TMPDIR:-/tmp}/ralph_jsonl.XXXXXX")"
  pipe_rc_file="$(mktemp "${TMPDIR:-/tmp}/ralph_rc.XXXXXX")"
  jq_rc_file="$(mktemp "${TMPDIR:-/tmp}/ralph_jq_rc.XXXXXX")"
  : > "$output_file"
  : > "$raw_jsonl"
  echo "0" > "$pipe_rc_file"
  echo "0" > "$jq_rc_file"

  # BUG FIX #10: Clean up temp files (and monitor) when function returns
  local _iter_tmp_files=("$output_file" "$raw_jsonl" "$pipe_rc_file" "$jq_rc_file")
  local _monitor_pid=""
  # shellcheck disable=SC2329,SC2317 # invoked by RETURN trap below
  _cleanup_iteration_tmp() {
    if [[ -n "${_monitor_pid:-}" ]]; then
      kill "$_monitor_pid" 2>/dev/null || true
      wait "$_monitor_pid" 2>/dev/null || true
    fi
    rm -f ${_iter_tmp_files[@]+"${_iter_tmp_files[@]}"} 2>/dev/null || true
  }
  trap _cleanup_iteration_tmp RETURN

  # Background monitor: print inline status or render dashboard
  local _use_monitor=false
  if [[ "${UI_MODE:-full}" == "dashboard" ]] && is_tty; then
    _use_monitor=true
  elif [[ "$QUIET" == "false" && "${UI_MODE:-full}" == "full" && "${SHOW_STATUS_LINE:-true}" == "true" ]] && is_tty; then
    _use_monitor=true
  fi

  if [[ "$_use_monitor" == "true" ]]; then
    local _monitor_interval=2
    [[ "${UI_MODE:-full}" == "dashboard" ]] && _monitor_interval=2
    (
      sleep 1  # Short initial delay, then update every _monitor_interval
      while true; do
        local _now _elapsed _tc _pt
        _now="$(date '+%s')"
        _elapsed=$(( _now - iter_started_epoch ))
        if [[ "$ENGINE" == "codex" ]]; then
          _tc="$(count_tool_calls_from_codex_jsonl "$raw_jsonl" 2>/dev/null || echo 0)"
        else
          _tc="$(count_tool_calls_from_jsonl "$raw_jsonl" 2>/dev/null || echo 0)"
        fi
        [[ -z "$_tc" ]] && _tc=0
        _pt="$(grep 'PICKING: ' "$output_file" 2>/dev/null | sed 's/.*PICKING: //' | head -1 || true)"

        if [[ "${UI_MODE:-full}" == "dashboard" ]]; then
          render_dashboard "$raw_jsonl" "$output_file" "$iter_started_epoch"
        else
          print_status_line "$_elapsed" "$ITERATION_TIMEOUT" "$_tc" "$MAX_TOOL_CALLS" "$_pt"
        fi
        sleep "$_monitor_interval"
      done
    ) &
    _monitor_pid=$!
  fi

  # Run the AI engine
  run_engine "$prompt_content" "$ENGINE" "$raw_jsonl" "$output_file" \
    "$pipe_rc_file" "$jq_rc_file" "$ITERATION_TIMEOUT" "$quiet_for_engine" \
    "$CODEX_EXEC_FLAGS" "${LOG_FILE:-}"

  # Stop the background monitor and clear its in-place status line
  if [[ -n "$_monitor_pid" ]]; then
    kill "$_monitor_pid" 2>/dev/null || true
    wait "$_monitor_pid" 2>/dev/null || true
    _monitor_pid=""
    clear_status_line
  fi

  local claude_exit_code jq_exit_code
  claude_exit_code="$(cat "$pipe_rc_file" 2>/dev/null || echo 0)"
  [[ -z "$claude_exit_code" ]] && claude_exit_code=0
  jq_exit_code="$(cat "$jq_rc_file" 2>/dev/null || echo 0)"
  [[ -z "$jq_exit_code" ]] && jq_exit_code=0

  local failure_reason=""
  if [[ $claude_exit_code -eq 124 ]]; then
    failure_reason="timeout after $(fmt_hms "$ITERATION_TIMEOUT")"
  elif [[ $claude_exit_code -ne 0 ]]; then
    failure_reason="${ENGINE} exited with code $claude_exit_code"
  elif [[ $jq_exit_code -ne 0 ]]; then
    failure_reason="jq parse error (exit code $jq_exit_code)"
  fi

  state_after="$(get_file_state_hash)"
  if [[ "$state_before" != "$state_after" ]]; then
    files_changed=true
  fi

  local tool_count
  if [[ "$ENGINE" == "codex" ]]; then
    tool_count="$(count_tool_calls_from_codex_jsonl "$raw_jsonl" || echo 0)"
  else
    tool_count="$(count_tool_calls_from_jsonl "$raw_jsonl" || echo 0)"
  fi
  [[ -z "$tool_count" ]] && tool_count=0

  local picked_task failed_task task_completed
  picked_task="$(grep "PICKING: " "$output_file" 2>/dev/null | sed 's/.*PICKING: //' | head -1 || true)"
  failed_task="$(grep "ATTEMPT_FAILED: " "$output_file" 2>/dev/null | sed 's/.*ATTEMPT_FAILED: //' | head -1 || true)"

  task_completed=false
  if grep -qE "^(DONE:|MARKING COMPLETE:)" "$output_file" 2>/dev/null; then
    task_completed=true
  fi

  # Update claims for parallel coordination
  if [[ "$WORKER_ID" -gt 0 ]]; then
    if [[ "$task_completed" == "true" || -n "$failed_task" ]]; then
      clear_claim "$WORKER_ID"
    elif [[ -n "$picked_task" ]]; then
      update_claim "$WORKER_ID" "$picked_task"
    fi
  fi

  local exit_signal=false
  if grep -q "EXIT_SIGNAL: true" "$output_file" 2>/dev/null; then
    exit_signal=true
  fi

  if [[ -z "$failure_reason" && "$task_completed" == "false" && "$tool_count" -ge "$MAX_TOOL_CALLS" ]]; then
    failure_reason="excessive tool calls ($tool_count) without completion"
  fi

  local iter_end_epoch iter_elapsed
  iter_end_epoch="$(date '+%s')"
  iter_elapsed=$(( iter_end_epoch - iter_started_epoch ))

  ITERATION_COUNT=$((ITERATION_COUNT + 1))

  local task_display
  task_display="${picked_task:-"(none)"}"

  # Determine normalized status label
  local status="INFO"
  if [[ "$task_completed" == "true" ]]; then
    status="OK"
  elif [[ -n "$failure_reason" ]]; then
    status="FAIL"
  elif [[ "$tool_count" -eq 0 && "$files_changed" == "false" && -z "$picked_task" ]]; then
    status="EMPTY"
  fi

  # Record in history trail
  record_iteration_result "$status"

  # Compute attempt info for display
  local attempt_info=""
  if [[ -n "$picked_task" && "$status" != "OK" ]]; then
    local current_attempts
    current_attempts="$(get_attempts "$picked_task" 2>/dev/null || echo 0)"
    if [[ "$current_attempts" -gt 0 ]]; then
      attempt_info="attempt $((current_attempts + 1))/${MAX_ATTEMPTS}"
    fi
  fi

  # Update counters and terminal title based on status
  if [[ "$status" == "OK" ]]; then
    COMPLETED_COUNT=$((COMPLETED_COUNT + 1))
    set_smart_title "completed" "$iteration" "$COMPLETED_COUNT" "$FAILED_COUNT" "$picked_task"
    bell completion
    notify "Ralph: Task Completed" "$task_display in $(fmt_hms "$iter_elapsed")"
  elif [[ "$status" == "FAIL" ]]; then
    FAILED_COUNT=$((FAILED_COUNT + 1))
    set_smart_title "failed" "$iteration" "$COMPLETED_COUNT" "$FAILED_COUNT" "$picked_task"
    notify "Ralph: Task Failed" "$task_display: $failure_reason"
  elif [[ "$status" == "EMPTY" ]]; then
    FAILED_COUNT=$((FAILED_COUNT + 1))
    set_smart_title "empty" "$iteration" "$COMPLETED_COUNT" "$FAILED_COUNT" ""
    [[ -n "${LOG_FILE:-}" && "${LOG_FORMAT:-text}" == "text" ]] && echo "WARNING: Empty iteration - no tool calls, no file changes" >> "$LOG_FILE"
  else
    set_smart_title "running" "$iteration" "$COMPLETED_COUNT" "$FAILED_COUNT" ""
  fi

  # Build signal booleans for the result card
  local picked_yes done_yes exit_yes explicit_fail_yes
  picked_yes="$([[ -n "$picked_task" ]] && echo "yes" || echo "no")"
  done_yes="$([[ "$task_completed" == "true" ]] && echo "yes" || echo "no")"
  exit_yes="$([[ "$exit_signal" == "true" ]] && echo "yes" || echo "no")"
  explicit_fail_yes="$([[ -n "$failed_task" ]] && echo "yes" || echo "no")"

  # JSONL event: iteration_end
  log_event_jsonl "iteration_end" \
    "iteration" "$iteration" \
    "run_id" "$RUN_ID" \
    "status" "$status" \
    "task" "$task_display" \
    "elapsed" "$iter_elapsed" \
    "tools" "$tool_count" \
    "files_changed" "$files_changed"

  # Update run elapsed
  run_elapsed=$(( iter_end_epoch - STARTED_EPOCH ))

  # Print final status UI
  if [[ "${UI_MODE:-full}" == "dashboard" ]]; then
    local skipped_now
    skipped_now="$(get_skipped_tasks | wc -l | tr -d ' ')"
    write_dashboard_state "$iteration" "$status" "$picked_task" \
      "$COMPLETED_COUNT" "$FAILED_COUNT" "$skipped_now" \
      "$iter_elapsed" "$ITERATION_TIMEOUT" "$tool_count" "$MAX_TOOL_CALLS" \
      "$iter_quote" "$run_elapsed"
    render_dashboard "$raw_jsonl" "$output_file" "$iter_started_epoch"
    sleep 2  # Brief pause to show final state
  elif [[ "${UI_MODE:-full}" == "full" ]]; then
    echo ""
    render_dynamic_banner "$iteration" "$time_short" "$iter_quote" "$status" \
      "$COMPLETED_COUNT" "$FAILED_COUNT" "$skipped_count" \
      "$iter_elapsed" "$ITERATION_TIMEOUT" "$tool_count" "$MAX_TOOL_CALLS" \
      "$picked_task" "$attempt_info" "$run_elapsed"

    # Print the result card
    print_iteration_result_card \
      "$status" \
      "$(fmt_hms "$iter_elapsed")" \
      "$task_display" \
      "$failure_reason" \
      "$tool_count" "$MAX_TOOL_CALLS" \
      "$files_changed" \
      "$jq_exit_code" "$claude_exit_code" \
      "$picked_yes" "$done_yes" "$exit_yes" "$explicit_fail_yes" \
      "$output_file" \
      "$attempt_info"
  elif [[ "${UI_MODE:-full}" == "compact" ]]; then
    print_iteration_summary_line \
      "$status" \
      "$(fmt_hms "$iter_elapsed")" \
      "$task_display" \
      "$failure_reason" \
      "$tool_count"
  fi

  # Additional warning if completed but no file changes
  if [[ "$status" == "OK" && "$files_changed" == "false" ]]; then
    log_warn "Completed signal but no file changes detected"
  fi

  if [[ "$exit_signal" == "true" ]]; then
    echo ""
    hr_green
    log_ok "${BOLD}EXIT_SIGNAL detected - All tasks complete!${NC}"
    hr_green

    # In multi-worker mode, signal other workers and return special code
    if [[ "$NUM_WORKERS" -gt 1 ]]; then
      signal_exit
      clear_claim "$WORKER_ID"
      return 99
    fi

    set_smart_title "complete" "$iteration" "$COMPLETED_COUNT" "$FAILED_COUNT" ""
    # BUG FIX #4: Return instead of exit - let the caller handle cleanup
    if [[ "$EXIT_ON_COMPLETE" == "true" ]]; then
      return 98
    else
      log_info "Continuing loop (--no-exit-on-complete mode)"
      return 0
    fi
  fi

  local picked_safe failed_safe
  picked_safe="$(sanitize_tty_text "$picked_task")"
  failed_safe="$(sanitize_tty_text "$failed_task")"

  if [[ -n "$failed_task" ]]; then
    local attempt_count
    attempt_count="$(increment_attempts "$failed_task")"

    echo ""
    log_err "ATTEMPT FAILED (explicit): ${failed_safe}"
    log_err "Attempt ${attempt_count} of ${MAX_ATTEMPTS}"

    if [[ "$attempt_count" -ge "$MAX_ATTEMPTS" ]]; then
      mark_skipped "$failed_task"
      log_warn "SKIPPING: Task exceeded max attempts"
      [[ -n "${LOG_FILE:-}" && "${LOG_FORMAT:-text}" == "text" ]] && echo "SKIPPED: $failed_task (exceeded $MAX_ATTEMPTS attempts)" >> "$LOG_FILE"
      log_event_jsonl "task_skipped" "task" "$failed_task" "attempts" "$attempt_count"
    else
      [[ -n "${LOG_FILE:-}" && "${LOG_FORMAT:-text}" == "text" ]] && echo "ATTEMPT $attempt_count FAILED: $failed_task" >> "$LOG_FILE"
    fi

  elif [[ -n "$picked_task" && "$task_completed" == "false" ]]; then
    local attempt_count reason
    attempt_count="$(increment_attempts "$picked_task")"
    reason="${failure_reason:-not completed}"
    local reason_safe
    reason_safe="$(sanitize_tty_text "$reason")"

    echo ""
    log_err "ATTEMPT FAILED: ${picked_safe}"
    log_err "Reason: ${reason_safe}"
    log_err "Attempt ${attempt_count} of ${MAX_ATTEMPTS}"

    if [[ "$attempt_count" -ge "$MAX_ATTEMPTS" ]]; then
      mark_skipped "$picked_task"
      log_warn "SKIPPING: Task exceeded max attempts"
      [[ -n "${LOG_FILE:-}" && "${LOG_FORMAT:-text}" == "text" ]] && echo "SKIPPED: $picked_task ($reason, exceeded $MAX_ATTEMPTS attempts)" >> "$LOG_FILE"
      log_event_jsonl "task_skipped" "task" "$picked_task" "reason" "$reason" "attempts" "$attempt_count"
    else
      [[ -n "${LOG_FILE:-}" && "${LOG_FORMAT:-text}" == "text" ]] && echo "ATTEMPT $attempt_count FAILED: $picked_task ($reason)" >> "$LOG_FILE"
    fi

  elif [[ -n "$failure_reason" ]]; then
    echo ""
    local failure_safe
    failure_safe="$(sanitize_tty_text "$failure_reason")"
    log_err "ITERATION FAILED: ${failure_safe}"
    [[ -n "${LOG_FILE:-}" && "${LOG_FORMAT:-text}" == "text" ]] && echo "ITERATION FAILED: $failure_reason" >> "$LOG_FILE"
  fi

}
