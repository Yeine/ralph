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
  local width content_width
  width="$(get_box_width)"
  content_width=$(( width - 4 ))  # 2 borders + 2 spaces

  local vlen
  vlen="$(visual_length "$content")"
  if [[ "$vlen" -gt "$content_width" ]]; then
    # Truncate: strip ANSI, cut to fit, add ellipsis
    local plain
    plain="$(strip_ansi "$content")"
    content="${plain:0:$((content_width - 1))}…"
    vlen="$content_width"
  fi

  # Pad with spaces so the right border aligns
  local pad=$(( content_width - vlen ))
  printf "%b│%b %b%*s %b│%b\n" "${DIM}${BLUE}" "${NC}" "$content" "$pad" "" "${DIM}${BLUE}" "${NC}"
}

box_title() {
  local title="$1"
  printf "%b\n" "${BOLD}${MAGENTA}${title}${NC}"
}

# -----------------------------------------------------------------------------
# String helpers
# -----------------------------------------------------------------------------

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
  if [[ "$max" -le 1 ]]; then
    echo "…"
    return 0
  fi
  # Strip ANSI before truncating to avoid cutting mid-sequence
  local plain
  plain="$(strip_ansi "$s")"
  echo "${plain:0:$((max-1))}…"
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
  # Remove all CSI sequences: ESC[ ... m (colors, bold, dim, etc.)
  printf '%s' "$s" | sed $'s/\033\[[0-9;]*m//g'
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
# Dynamic banner — fixed at top of scroll region, updated in-place
# Always renders exactly 5 lines: box_top + line1 + line2 + quote + box_bottom
# -----------------------------------------------------------------------------

# Banner height is constant so scroll region stays stable (used in iteration.sh)
# shellcheck disable=SC2034
BANNER_LINES=5

# Banner state flag — set by init_banner, cleared by reset_scroll_region.
_BANNER_ACTIVE=0

# Banner update interval in seconds (used by the monitor loop in iteration.sh).
# shellcheck disable=SC2034
BANNER_UPDATE_INTERVAL=2

# Set terminal scroll region so lines below the banner scroll independently.
_setup_scroll_region() {
  is_tty || return 0
  local term_rows
  term_rows="$(tput lines 2>/dev/null || echo 24)"
  local banner_end=$(( BANNER_LINES + 1 ))
  printf '\033[%d;%dr' "$banner_end" "$term_rows"   # set scroll region
  printf '\033[%d;1H' "$banner_end"                  # move cursor there
}

# Reset scroll region to full terminal.
reset_scroll_region() {
  is_tty || return 0
  _BANNER_ACTIVE=0
  printf '\033[r'           # reset to full terminal
}

# Reapply scroll region after terminal resize (SIGWINCH).
# No-op when no banner is active.
reapply_scroll_region() {
  [[ "$_BANNER_ACTIVE" -eq 1 ]] || return 0
  _setup_scroll_region
}

# Initialize the dynamic banner: clear screen, render at row 1, set scroll region.
# Call this once at iteration start (TTY + non-quiet only).
init_banner() {
  is_tty || return 0
  _BANNER_ACTIVE=1
  printf '\033[2J\033[H'    # clear screen, cursor to row 1 col 1
  render_dynamic_banner "$@"
  _setup_scroll_region
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
  local task_slot=""
  if [[ -n "$picked_task" ]]; then
    task_slot="$(truncate_ellipsis "$picked_task" 40)"
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
  line2="${DIM}${time_short}${NC}  ${DIM}|${NC}  ${GREEN}v${completed}${NC} ${RED}x${failed}${NC} ${YELLOW}>${skipped}${NC}  ${DIM}|${NC}  ${time_color}T ${elapsed_sec}s/${iter_timeout}s${NC}  ${DIM}|${NC}  ${tools_color}# ${tool_count}/${max_tools}${NC}"

  # Quote line (always present for fixed height)
  local line3="${DIM}${MAGENTA}\"${quote}\"${NC}"

  box_top
  box_line "$line1"
  box_line "$line2"
  box_line "$line3"
  box_bottom
}

# Redraw the banner in-place without disturbing the scroll region.
# Moves to row 1, redraws, then repositions cursor at the bottom of the
# scroll region.  We intentionally avoid \033[s / \033[u (save/restore cursor)
# because the background monitor races with foreground output, causing the
# cursor to jump back to a stale position.  Moving to the bottom is safe:
# the scroll region auto-scrolls so new output always appears at the bottom.
update_banner_inplace() {
  is_tty || return 0
  printf '\033[1;1H'         # move to row 1, col 1
  render_dynamic_banner "$@"
  printf '\033[999;1H'       # move to bottom of scroll region
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

  echo ""
  hr

  # One-line summary (the key takeaway)
  case "$status" in
    OK)
      printf "  %b\n" "${GREEN}v${NC}  Completed ${WHITE}${task_display}${NC} in ${CYAN}${iter_elapsed_fmt}${NC} ${DIM}(${tool_count} tool calls)${NC}"
      ;;
    FAIL)
      printf "  %b\n" "${RED}x${NC}  Failed ${WHITE}${task_display}${NC} after ${CYAN}${iter_elapsed_fmt}${NC}: ${RED}${failure_reason}${NC}"
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
    while IFS= read -r l; do
      printf "    %b\n" "${DIM}${l}${NC}"
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
