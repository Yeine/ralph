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
# UI sizing constants
# -----------------------------------------------------------------------------
UI_MIN_WIDTH=36
UI_MAX_WIDTH=96
UI_FALLBACK_WIDTH=80
BOX_TERM_MIN_WIDTH=52
BOX_TERM_MAX_WIDTH=96
BOX_MIN_WIDTH=50
STATUS_TASK_MAX=40
BANNER_TASK_MAX=28
UI_ASCII=false
UI_USE_ASCII=false
UI_HR_CHAR="─"
UI_BOX_H="─"
UI_BOX_V="│"
UI_BOX_TL="╭"
UI_BOX_TR="╮"
UI_BOX_BL="╰"
UI_BOX_BR="╯"
UI_ELLIPSIS="…"

setup_ui_charset() {
  local ascii="false"
  case "${UI_ASCII:-}" in
    1|true|TRUE|yes|YES) ascii="true" ;;
  esac
  case "${RALPH_ASCII:-}" in
    1|true|TRUE|yes|YES) ascii="true" ;;
  esac
  if [[ "$ascii" != "true" ]]; then
    if ! is_tty; then
      ascii="true"
    else
      local loc="${LC_ALL:-${LANG:-}}"
      if [[ -n "$loc" ]]; then
        if [[ "$loc" == "C" || "$loc" == "POSIX" ]]; then
          ascii="true"
        elif [[ "$loc" != *"UTF-8"* && "$loc" != *"utf8"* && "$loc" != *"UTF8"* ]]; then
          ascii="true"
        fi
      fi
    fi
  fi

  if [[ "$ascii" == "true" ]]; then
    UI_USE_ASCII=true
    UI_HR_CHAR="-"
    UI_BOX_H="-"
    UI_BOX_V="|"
    UI_BOX_TL="+"
    UI_BOX_TR="+"
    UI_BOX_BL="+"
    UI_BOX_BR="+"
    UI_ELLIPSIS="..."
  else
    UI_USE_ASCII=false
    UI_HR_CHAR="─"
    UI_BOX_H="─"
    UI_BOX_V="│"
    UI_BOX_TL="╭"
    UI_BOX_TR="╮"
    UI_BOX_BL="╰"
    UI_BOX_BR="╯"
    UI_ELLIPSIS="…"
  fi
}

# -----------------------------------------------------------------------------
# Terminal width detection (shared helper, eliminates duplication)
# -----------------------------------------------------------------------------
_get_terminal_width() {
  local min="${1:-$UI_MIN_WIDTH}" max="${2:-$UI_MAX_WIDTH}"
  local width="$UI_FALLBACK_WIDTH"
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
  local color="${1:-$BLUE}" ch="$UI_HR_CHAR"
  local width
  width="$(_get_terminal_width "$UI_MIN_WIDTH" "$UI_MAX_WIDTH")"
  printf "%b\n" "${color}$(printf "%*s" "$width" "" | tr ' ' "$ch")${NC}"
}

hr()       { _hr_colored "$BLUE"; }
hr_green() { _hr_colored "$GREEN"; }

# -----------------------------------------------------------------------------
# Box drawing with rounded corners
# -----------------------------------------------------------------------------
get_box_width() {
  local width
  width="$(_get_terminal_width "$BOX_TERM_MIN_WIDTH" "$BOX_TERM_MAX_WIDTH")"
  # Box is 2 chars narrower
  width=$(( width - 2 ))
  width=$(( width > BOX_MIN_WIDTH ? width : BOX_MIN_WIDTH ))
  echo "$width"
}

box_top() {
  local width
  width="$(get_box_width)"
  printf "%b\n" "${DIM}${BLUE}${UI_BOX_TL}$(printf '%*s' "$((width - 2))" '' | tr ' ' "$UI_BOX_H")${UI_BOX_TR}${NC}"
}

box_bottom() {
  local width
  width="$(get_box_width)"
  printf "%b\n" "${DIM}${BLUE}${UI_BOX_BL}$(printf '%*s' "$((width - 2))" '' | tr ' ' "$UI_BOX_H")${UI_BOX_BR}${NC}"
}

box_line() {
  local content="$1"
  local width content_width
  width="$(get_box_width)"
  content_width=$(( width - 4 ))  # 2 borders + 2 spaces

  local vlen
  vlen="$(visual_length "$content")"
  if [[ "$vlen" -gt "$content_width" ]]; then
    content="$(truncate_ellipsis "$content" "$content_width")"
    vlen="$(visual_length "$content")"
  fi

  # Pad with spaces so the right border aligns
  local pad=$(( content_width - vlen ))
  printf "%b%s%b %b%*s %b%s%b\n" "${DIM}${BLUE}" "$UI_BOX_V" "${NC}" "$content" "$pad" "" "${DIM}${BLUE}" "$UI_BOX_V" "${NC}"
}

box_title() {
  local title="$1"
  printf "%b\n" "${BOLD}${MAGENTA}${title}${NC}"
}

# -----------------------------------------------------------------------------
# String helpers
# -----------------------------------------------------------------------------

# Sanitize user-controlled text for safe printf %b output.
# - Removes control characters that can break layout
# - Escapes backslashes to neutralize printf escape processing
sanitize_tty_text() {
  local s="$1"
  s="${s//$'\r'/ }"
  s="${s//$'\n'/ }"
  s="${s//$'\t'/ }"
  s="${s//$'\033'/}"
  s="${s//\\/\\\\}"
  printf '%s' "$s"
}

# Safe string truncation with ellipsis (ANSI-aware)
truncate_ellipsis() {
  local s="$1" max="$2"
  if [[ -z "$s" || "$max" -le 0 ]]; then
    echo ""
    return 0
  fi
  local vlen
  vlen="$(visual_length "$s")"
  if [[ "$vlen" -le "$max" ]]; then
    echo "$s"
    return 0
  fi
  local ell="${UI_ELLIPSIS}"
  local ell_len="${#ell}"
  if [[ "$max" -le "$ell_len" ]]; then
    echo "${ell:0:$max}"
    return 0
  fi
  # Strip ANSI before truncating to avoid cutting mid-sequence
  local plain
  plain="$(strip_ansi "$s")"
  echo "${plain:0:$((max-ell_len))}${ell}"
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

# Strip ANSI escape sequences from a string (pipe helper)
strip_ansi() {
  local s="$1"
  # Remove both actual ESC sequences and literal "\033[" color codes.
  printf '%s' "$s" | sed $'s/\033\[[0-9;]*m//g; s/\\\\033\\[[0-9;]*m//g'
}

# Return the visual column width of a string (ANSI codes excluded)
visual_length() {
  local stripped
  stripped="$(strip_ansi "$1")"
  echo "${#stripped}"
}

# Pad a string with trailing spaces to reach a target visual width.
# If the string is already wider, it is returned as-is.
pad_to_width() {
  local s="$1" target_width="$2"
  local vlen
  vlen="$(visual_length "$s")"
  if [[ "$vlen" -ge "$target_width" ]]; then
    printf '%b' "$s"
  else
    printf '%b%*s' "$s" $(( target_width - vlen )) ""
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
  grep -E "^(PICKING|WRITING|TESTING|PASSED|MARKING|DONE|REMAINING|EXIT_SIGNAL|ATTEMPT_FAILED|>>> )" -- "$file" 2>/dev/null \
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
    printf "\r%b\033[K" "${BLUE}T${NC}  Next iteration in ${YELLOW}${i}s${NC}... (Ctrl+C to stop)"
    sleep 1
  done
  printf "\r\033[K"  # clear line
}

# -----------------------------------------------------------------------------
# Dynamic banner — printed as normal scrolling output (no cursor tricks)
# Always renders exactly 5 lines: box_top + line1 + line2 + quote + box_bottom
# -----------------------------------------------------------------------------

# Banner height constant (5 lines).
# shellcheck disable=SC2034
BANNER_LINES=5

# No-op stubs — scroll regions removed for reliability.
reset_scroll_region() { :; }
reapply_scroll_region() { :; }

# Print a compact inline status line (called periodically by the monitor).
print_status_line() {
  local elapsed_sec="$1" iter_timeout="$2"
  local tool_count="$3" max_tools="$4"
  local picked_task="$5"

  local task_display="" picked_safe=""
  if [[ -n "$picked_task" ]]; then
    picked_safe="$(sanitize_tty_text "$picked_task")"
    task_display=" | $(truncate_ellipsis "$picked_safe" "$STATUS_TASK_MAX")"
  fi

  local time_color tools_color elapsed_pct=0 tools_pct=0
  if [[ "$iter_timeout" -gt 0 ]]; then
    elapsed_pct=$(( (elapsed_sec * 100) / iter_timeout ))
  fi
  if [[ "$max_tools" -gt 0 ]]; then
    tools_pct=$(( (tool_count * 100) / max_tools ))
  fi
  time_color="$(color_by_pct "$elapsed_pct" 60 85)"
  tools_color="$(color_by_pct "$tools_pct" 60 85)"

  printf "  %b\n" "${DIM}~${NC} ${time_color}${elapsed_sec}s/${iter_timeout}s${NC} ${tools_color}#${tool_count}/${max_tools}${NC}${task_display}"
}

# Render the dynamic banner (exactly BANNER_LINES lines).
# Used for both initial render and in-place updates.
render_dynamic_banner() {
  local iteration="$1"
  local time_short="$2"
  local quote="$3"
  local state_label="$4"
  local completed="$5" failed="$6" skipped="$7"
  local elapsed_sec="$8" iter_timeout="$9"
  local tool_count="${10}" max_tools="${11}"
  local picked_task="${12:-}"

  # State badge color
  local badge_color="$BLUE"
  case "$state_label" in
    OK|COMPLETED|SUCCESS) badge_color="$GREEN" ;;
    FAIL|FAILED|ERROR|TIMEOUT) badge_color="$RED" ;;
    EMPTY|WARN) badge_color="$YELLOW" ;;
  esac

  # Task slot
  local task_slot="" picked_safe=""
  if [[ -n "$picked_task" ]]; then
    picked_safe="$(sanitize_tty_text "$picked_task")"
    task_slot="$(truncate_ellipsis "$picked_safe" "$BANNER_TASK_MAX")"
  fi

  # Line 1: Iter + Task + State
  local line1
  if [[ -n "$task_slot" ]]; then
    line1="${BOLD}${CYAN}#${iteration}${NC} ${DIM}|${NC} ${WHITE}${task_slot}${NC} ${DIM}|${NC} ${BOLD}${badge_color}${state_label}${NC}"
  else
    line1="${BOLD}${CYAN}#${iteration}${NC} ${DIM}|${NC} ${BOLD}${badge_color}${state_label}${NC}"
  fi

  # Meters
  local elapsed_pct=0 tools_pct=0 time_color tools_color
  if [[ "$iter_timeout" -gt 0 ]]; then
    elapsed_pct=$(( (elapsed_sec * 100) / iter_timeout ))
    [[ "$elapsed_pct" -gt 999 ]] && elapsed_pct=999
  fi
  if [[ "$max_tools" -gt 0 ]]; then
    tools_pct=$(( (tool_count * 100) / max_tools ))
    [[ "$tools_pct" -gt 999 ]] && tools_pct=999
  fi
  time_color="$(color_by_pct "$elapsed_pct" 60 85)"
  tools_color="$(color_by_pct "$tools_pct" 60 85)"

  # Line 2: Time + counts + meters
  local line2
  line2="${DIM}${time_short}${NC} ${DIM}|${NC} ${GREEN}C${completed}${NC} ${RED}F${failed}${NC} ${YELLOW}S${skipped}${NC} ${DIM}|${NC} ${time_color}T ${elapsed_sec}s/${iter_timeout}s${NC} ${DIM}|${NC} ${tools_color}# ${tool_count}/${max_tools}${NC}"

  # Quote line (always present for fixed height)
  local line3=""
  if [[ -n "$quote" ]]; then
    line3="${DIM}${MAGENTA}\"${quote}\"${NC}"
  else
    line3="${DIM}${MAGENTA}${NC}"
  fi

  box_top
  box_line "$line1"
  box_line "$line2"
  box_line "$line3"
  box_bottom
}

print_iteration_summary_line() {
  local status="$1"
  local iter_elapsed_fmt="$2"
  local task_display="$3"
  local failure_reason="$4"
  local tool_count="$5"

  local task_safe failure_safe
  task_safe="$(sanitize_tty_text "$task_display")"
  failure_safe="$(sanitize_tty_text "$failure_reason")"

  case "$status" in
    OK)
      printf "  %b\n" "${GREEN}v${NC}  Completed ${WHITE}${task_safe}${NC} in ${CYAN}${iter_elapsed_fmt}${NC} ${DIM}(${tool_count} tool calls)${NC}"
      ;;
    FAIL)
      printf "  %b\n" "${RED}x${NC}  Failed ${WHITE}${task_safe}${NC} after ${CYAN}${iter_elapsed_fmt}${NC}: ${RED}${failure_safe}${NC}"
      ;;
    EMPTY)
      printf "  %b\n" "${YELLOW}!${NC}  Empty iteration ${DIM}(no tools, no changes, no task picked)${NC}"
      ;;
    *)
      printf "  %b\n" "${BLUE}i${NC}  Iteration finished in ${CYAN}${iter_elapsed_fmt}${NC}"
      ;;
  esac
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

  local task_safe failure_safe
  task_safe="$(sanitize_tty_text "$task_display")"
  failure_safe="$(sanitize_tty_text "$failure_reason")"

  echo ""
  hr

  # One-line summary (the key takeaway)
  case "$status" in
    OK)
      printf "  %b\n" "${GREEN}v${NC}  Completed ${WHITE}${task_safe}${NC} in ${CYAN}${iter_elapsed_fmt}${NC} ${DIM}(${tool_count} tool calls)${NC}"
      ;;
    FAIL)
      printf "  %b\n" "${RED}x${NC}  Failed ${WHITE}${task_safe}${NC} after ${CYAN}${iter_elapsed_fmt}${NC}: ${RED}${failure_safe}${NC}"
      ;;
    EMPTY)
      printf "  %b\n" "${YELLOW}!${NC}  Empty iteration ${DIM}(no tools, no changes, no task picked)${NC}"
      ;;
    *)
      printf "  %b\n" "${BLUE}i${NC}  Iteration finished in ${CYAN}${iter_elapsed_fmt}${NC}"
      ;;
  esac

  # Detailed metrics (dimmed — for debugging, not primary reading)
  printf "  %b\n" "${DIM}tools=${tool_count}/${max_tools}  files_changed=${files_changed}  jq=${jq_exit}  claude=${claude_exit}${NC}"
  printf "  %b\n" "${DIM}picked=${picked_yes} done=${done_yes} exit=${exit_yes} attempt_failed=${explicit_fail_yes}${NC}"

  # Signal trail (show for all statuses so user can see what happened)
  local lines
  lines="$(tail_signal_lines "$output_file" 6)"
  if [[ -n "$lines" ]]; then
    echo ""
    printf "  %b\n" "${DIM}Signals:${NC}"
    local line_safe
    while IFS= read -r l; do
      line_safe="$(sanitize_tty_text "$l")"
      printf "    %b\n" "${DIM}${line_safe}${NC}"
    done <<< "$lines"
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
