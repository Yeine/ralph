#!/usr/bin/env bash
# ui.sh - UX helpers: logging, horizontal rules, box drawing, banners, result cards

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log_info() { printf "%b\n" "${BLUE}i${NC}  $*"; }
log_ok()   { printf "%b\n" "${GREEN}v${NC}  $*"; }
log_warn() { printf "%b\n" "${YELLOW}!${NC}  $*"; }
log_err()  { printf "%b\n" "${RED}x${NC}  $*"; }
log_dim()  { printf "%b\n" "${DIM}$*${NC}"; }

# -----------------------------------------------------------------------------
# Terminal width detection (shared helper, eliminates duplication)
# -----------------------------------------------------------------------------
_get_terminal_width() {
  local min="${1:-36}" max="${2:-96}"
  local width=44
  if command -v tput >/dev/null 2>&1 && is_tty; then
    local cols
    cols="$(tput cols 2>/dev/null || echo 0)"
    if [[ "$cols" -gt 0 ]]; then
      width=$(( cols < max ? cols : max ))
      width=$(( width > min ? width : min ))
    fi
  fi
  echo "$width"
}

# -----------------------------------------------------------------------------
# Horizontal rules
# -----------------------------------------------------------------------------
_hr_colored() {
  local color="${1:-$BLUE}" ch="─"
  local width
  width="$(_get_terminal_width 36 96)"
  printf "%b\n" "${color}$(printf "%*s" "$width" "" | tr ' ' "$ch")${NC}"
}

hr()       { _hr_colored "$BLUE"; }
hr_green() { _hr_colored "$GREEN"; }

# -----------------------------------------------------------------------------
# Box drawing with rounded corners
# -----------------------------------------------------------------------------
get_box_width() {
  local width
  width="$(_get_terminal_width 52 96)"
  # Box is 2 chars narrower
  width=$(( width - 2 ))
  width=$(( width > 50 ? width : 50 ))
  echo "$width"
}

box_top() {
  local width
  width="$(get_box_width)"
  printf "%b\n" "${DIM}${BLUE}$(printf '%*s' "$((width))" '' | tr ' ' '-' | sed 's/^./╭/' | sed 's/.$/╮/')${NC}"
}

box_bottom() {
  local width
  width="$(get_box_width)"
  printf "%b\n" "${DIM}${BLUE}$(printf '%*s' "$((width))" '' | tr ' ' '-' | sed 's/^./╰/' | sed 's/.$/╯/')${NC}"
}

box_line() {
  local content="$1"
  printf "%b│%b %b %b│%b\n" "${DIM}${BLUE}" "${NC}" "$content" "${DIM}${BLUE}" "${NC}"
}

box_title() {
  local title="$1"
  printf "%b\n" "${BOLD}${MAGENTA}${title}${NC}"
}

# -----------------------------------------------------------------------------
# String helpers
# -----------------------------------------------------------------------------

# Safe string truncation with ellipsis
truncate_ellipsis() {
  local s="$1" max="$2"
  if [[ -z "$s" || "$max" -le 0 ]]; then
    echo ""
    return 0
  fi
  if [[ "${#s}" -le "$max" ]]; then
    echo "$s"
    return 0
  fi
  if [[ "$max" -le 1 ]]; then
    echo "…"
    return 0
  fi
  echo "${s:0:$((max-1))}…"
}

# Right align inside a given width
right_align() {
  local s="$1" width="$2"
  local len="${#s}"
  if [[ "$len" -ge "$width" ]]; then
    echo "$s"
  else
    printf "%*s%s" $((width - len)) "" "$s"
  fi
}

# Color helper based on percentage thresholds
color_by_pct() {
  local pct="$1" good="$2" warn="$3"
  if [[ "$pct" -lt "$good" ]]; then
    printf "%b" "${GREEN}"
  elif [[ "$pct" -lt "$warn" ]]; then
    printf "%b" "${YELLOW}"
  else
    printf "%b" "${RED}"
  fi
}

# Pull last N "signal" lines from output file for quick diagnostics
tail_signal_lines() {
  local file="$1" n="${2:-6}"
  [[ -f "$file" ]] || return 0
  grep -E "^(PICKING|WRITING|TESTING|PASSED|MARKING|DONE|REMAINING|EXIT_SIGNAL|ATTEMPT_FAILED|>>> )" "$file" 2>/dev/null \
    | tail -n "$n" || true
}

# Animated wait countdown (TTY only)
wait_with_countdown() {
  local seconds="$1"
  local i
  if [[ "${WAIT_COUNTDOWN:-true}" != "true" || "${QUIET:-false}" == "true" || ! -t 1 ]]; then
    sleep "$seconds"
    return 0
  fi

  for ((i=seconds; i>0; i--)); do
    printf "\r%b" "${BLUE}T${NC}  Next iteration in ${YELLOW}${i}s${NC}... (Ctrl+C to stop)   "
    sleep 1
  done
  printf "\r%*s\r" 80 ""  # clear line
}

# -----------------------------------------------------------------------------
# Iteration banner (2-line, compact)
# -----------------------------------------------------------------------------
render_iteration_banner() {
  local iteration="$1"
  local time_short="$2"
  local run_elapsed_fmt="$3"
  local quote="$4"
  local picked_task="$5"
  local completed="$6" failed="$7" skipped="$8"
  local attempts_now="$9" max_attempts="${10}"
  local tool_count="${11}" max_tools="${12}"
  local iter_timeout="${13}"
  local iter_started_epoch="${14}"
  local files_changed="${15:-}"
  local state_label="${16:-RUNNING}"

  local width
  width="$(get_box_width)"

  # Build meters
  local now elapsed_sec elapsed_pct tools_pct tools_color time_color
  now="$(date '+%s')"
  elapsed_sec=$(( now - iter_started_epoch ))
  if [[ "$iter_timeout" -gt 0 ]]; then
    elapsed_pct=$(( (elapsed_sec * 100) / iter_timeout ))
    [[ "$elapsed_pct" -gt 999 ]] && elapsed_pct=999
  else
    elapsed_pct=0
  fi

  if [[ "$max_tools" -gt 0 ]]; then
    tools_pct=$(( (tool_count * 100) / max_tools ))
    [[ "$tools_pct" -gt 999 ]] && tools_pct=999
  else
    tools_pct=0
  fi

  tools_color="$(color_by_pct "$tools_pct" 60 85)"
  time_color="$(color_by_pct "$elapsed_pct" 60 85)"

  # Task slot
  local task_slot=""
  if [[ -n "$picked_task" ]]; then
    task_slot="$(truncate_ellipsis "$picked_task" 48)"
  fi

  # Attempts slot (only show when task has prior attempts)
  local attempts_slot=""
  if [[ -n "$picked_task" && "$attempts_now" -ge 1 ]]; then
    attempts_slot=" | tries ${attempts_now}/${max_attempts}"
  fi

  # Git hint
  local git_slot=""
  if [[ -n "$files_changed" ]]; then
    if [[ "$files_changed" == "true" ]]; then
      git_slot=" | dirty"
    else
      git_slot=" | clean"
    fi
  fi

  # State badge color
  local badge_color="$BLUE"
  case "$state_label" in
    OK|COMPLETED|SUCCESS) badge_color="$GREEN" ;;
    FAIL|FAILED|ERROR|TIMEOUT|PARSE_FAIL|CLAUDE_FAIL) badge_color="$RED" ;;
    EMPTY|WARN) badge_color="$YELLOW" ;;
    RUNNING|IDLE) badge_color="$BLUE" ;;
  esac

  # Line 1: Iter + Task (if known) + State
  local line1
  if [[ -n "$task_slot" ]]; then
    line1="${BOLD}${CYAN}#${iteration}${NC} ${DIM}|${NC} ${WHITE}${task_slot}${NC}${DIM}${attempts_slot}${NC} ${DIM}|${NC} ${BOLD}${badge_color}${state_label}${NC}"
  else
    line1="${BOLD}${CYAN}#${iteration}${NC} ${DIM}|${NC} ${BOLD}${badge_color}${state_label}${NC}"
  fi

  # Line 2: Time + elapsed + counts + meters + mode hints
  local line2
  line2="${DIM}${time_short}${NC}  ${DIM}|${NC}  ${DIM}T${NC} ${CYAN}${run_elapsed_fmt}${NC}  ${DIM}|${NC}  ${GREEN}v${completed}${NC} ${RED}x${failed}${NC} ${YELLOW}>${skipped}${NC}  ${DIM}|${NC}  ${time_color}T ${elapsed_sec}s/${iter_timeout}s${NC}  ${DIM}|${NC}  ${tools_color}# ${tool_count}/${max_tools}${NC}${DIM}${git_slot}${NC}"

  echo ""
  box_top
  box_line "$line1"
  box_line "$line2"

  # Quote
  if [[ "${SHOW_QUOTE_EACH_ITERATION:-true}" == "true" && -n "$quote" ]]; then
    box_line "${DIM}${MAGENTA}\"${quote}\"${NC}"
  fi
  box_bottom
}

# -----------------------------------------------------------------------------
# End-of-iteration result card
# -----------------------------------------------------------------------------
print_iteration_result_card() {
  local status="$1"
  local iter_elapsed_fmt="$2"
  local task_display="$3"
  local failure_reason="$4"
  local tool_count="$5"
  local max_tools="$6"
  local files_changed="$7"
  local jq_exit="$8"
  local claude_exit="$9"
  local picked_yes="${10}"
  local done_yes="${11}"
  local exit_yes="${12}"
  local explicit_fail_yes="${13}"
  local output_file="${14}"

  local status_icon status_color
  case "$status" in
    OK)    status_icon="OK"; status_color="$GREEN" ;;
    FAIL)  status_icon="FAIL"; status_color="$RED" ;;
    EMPTY) status_icon="WARN"; status_color="$YELLOW" ;;
    *)     status_icon="INFO"; status_color="$BLUE" ;;
  esac

  local tools_pct tools_color
  if [[ "$max_tools" -gt 0 ]]; then
    tools_pct=$(( (tool_count * 100) / max_tools ))
  else
    tools_pct=0
  fi
  tools_color="$(color_by_pct "$tools_pct" 60 85)"

  echo ""
  hr
  printf "%b\n" "${BOLD}${status_color}${status_icon} Iteration Result${NC}"
  printf "  %-12s %b\n" "Outcome:"   "${BOLD}${status_color}${status}${NC}  ${DIM}|${NC} ${CYAN}${iter_elapsed_fmt}${NC}"
  printf "  %-12s %b\n" "Task:"      "${WHITE}${task_display}${NC}"

  if [[ -n "$failure_reason" ]]; then
    printf "  %-12s %b\n" "Reason:" "${RED}${failure_reason}${NC}"
  fi

  printf "  %-12s %b\n" "Metrics:" "tools=${tools_color}${tool_count}/${max_tools}${NC}  ${DIM}|${NC} files_changed=${CYAN}${files_changed}${NC}  ${DIM}|${NC} jq=${CYAN}${jq_exit}${NC}  ${DIM}|${NC} claude=${CYAN}${claude_exit}${NC}"
  printf "  %-12s %b\n" "Signals:" "picked=${CYAN}${picked_yes}${NC} done=${CYAN}${done_yes}${NC} exit=${CYAN}${exit_yes}${NC} attempt_failed=${CYAN}${explicit_fail_yes}${NC}"

  if [[ "$status" == "FAIL" || "$status" == "EMPTY" ]]; then
    echo ""
    printf "%b\n" "${BOLD}${MAGENTA}Last signals${NC}"
    local lines
    lines="$(tail_signal_lines "$output_file" 6)"
    if [[ -n "$lines" ]]; then
      while IFS= read -r l; do
        printf "  %b\n" "${DIM}${l}${NC}"
      done <<< "$lines"
    else
      printf "  %b\n" "${DIM}(no signal lines captured)${NC}"
    fi
  fi
  hr
}

# -----------------------------------------------------------------------------
# Run summary statistics
# -----------------------------------------------------------------------------
show_run_summary() {
  local now elapsed skipped_count
  now="$(date '+%s')"
  elapsed=$(( now - STARTED_EPOCH ))
  skipped_count="$(get_skipped_tasks | wc -l | tr -d ' ')"

  echo ""
  hr
  printf "%b\n" "${BOLD}${BLUE}Run Summary${NC}"
  printf "  %-16s %b\n" "Run ID:"     "${CYAN}${RUN_ID}${NC}"
  printf "  %-16s %b\n" "Duration:"   "${CYAN}$(fmt_hms "$elapsed")${NC}"
  printf "  %-16s %b\n" "Iterations:" "${CYAN}${ITERATION_COUNT}${NC}"
  printf "  %-16s %b\n" "Completed:"  "${GREEN}${COMPLETED_COUNT}${NC}"
  printf "  %-16s %b\n" "Failed:"     "${RED}${FAILED_COUNT}${NC}"
  printf "  %-16s %b\n" "Skipped:"    "${YELLOW}${skipped_count}${NC}"
  hr
}
