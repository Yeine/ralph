#!/usr/bin/env bash
# shellcheck disable=SC2034  # Variables are used across sourced lib files
# ui.sh - UX helpers: logging, box drawing, banners, spinners, progress bars,
#          dashboard mode, worker panel, error context boxes, history trail

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log_info() { printf "%b\n" "${BLUE}i${NC}  $*"; }
log_ok() { printf "%b\n" "${GREEN}v${NC}  $*"; }
log_warn() { printf "%b\n" "${YELLOW}!${NC}  $*"; }
log_err() { printf "%b\n" "${RED}x${NC}  $*"; }
log_dim() { printf "%b\n" "${DIM}$*${NC}"; }

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
UI_BOX_ML="├"
UI_BOX_MR="┤"
UI_ELLIPSIS="…"
UI_SYM_OK="✓"
UI_SYM_FAIL="✗"
UI_SYM_SKIP="⊘"

# Spinner frames
SPINNER_FRAMES_UNICODE=("⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧" "⠇" "⠏")
# shellcheck disable=SC1003
SPINNER_FRAMES_ASCII=("|" "/" "-" '\')
SPINNER_TICK=0

# Progress bar characters
PROGRESS_FILL_UNICODE="█"
PROGRESS_EMPTY_UNICODE="░"
PROGRESS_FILL_ASCII="#"
PROGRESS_EMPTY_ASCII="-"

# Iteration history trail
ITERATION_HISTORY=()
HISTORY_MAX=30

# History symbols
HISTORY_OK_UNICODE="✓"
HISTORY_FAIL_UNICODE="✗"
HISTORY_EMPTY_UNICODE="⊘"
HISTORY_INFO_UNICODE="·"
HISTORY_OK_ASCII="+"
HISTORY_FAIL_ASCII="x"
HISTORY_EMPTY_ASCII="o"
HISTORY_INFO_ASCII="."

setup_ui_charset() {
  local ascii="false"
  case "${UI_ASCII:-}" in
    1 | true | TRUE | yes | YES) ascii="true" ;;
  esac
  case "${RALPH_ASCII:-}" in
    1 | true | TRUE | yes | YES) ascii="true" ;;
  esac
  if [[ $ascii != "true" ]]; then
    if ! is_tty; then
      ascii="true"
    else
      local loc="${LC_ALL:-${LANG:-}}"
      if [[ -n $loc ]]; then
        if [[ $loc == "C" || $loc == "POSIX" ]]; then
          ascii="true"
        elif [[ $loc != *"UTF-8"* && $loc != *"utf8"* && $loc != *"UTF8"* ]]; then
          ascii="true"
        fi
      fi
    fi
  fi

  if [[ $ascii == "true" ]]; then
    UI_USE_ASCII=true
    UI_HR_CHAR="-"
    UI_BOX_H="-"
    UI_BOX_V="|"
    UI_BOX_TL="+"
    UI_BOX_TR="+"
    UI_BOX_BL="+"
    UI_BOX_BR="+"
    UI_BOX_ML="+"
    UI_BOX_MR="+"
    UI_ELLIPSIS="..."
    UI_SYM_OK="+"
    UI_SYM_FAIL="x"
    UI_SYM_SKIP="o"
  else
    UI_USE_ASCII=false
    UI_HR_CHAR="─"
    UI_BOX_H="─"
    UI_BOX_V="│"
    UI_BOX_TL="╭"
    UI_BOX_TR="╮"
    UI_BOX_BL="╰"
    UI_BOX_BR="╯"
    UI_BOX_ML="├"
    UI_BOX_MR="┤"
    UI_ELLIPSIS="…"
    UI_SYM_OK="✓"
    UI_SYM_FAIL="✗"
    UI_SYM_SKIP="⊘"
  fi
}

# -----------------------------------------------------------------------------
# Terminal width detection (shared helper)
# -----------------------------------------------------------------------------
_get_terminal_width() {
  local min="${1:-$UI_MIN_WIDTH}" max="${2:-$UI_MAX_WIDTH}"
  local width="$UI_FALLBACK_WIDTH"
  if command -v tput >/dev/null 2>&1 && is_tty; then
    local cols
    cols="$(tput cols 2>/dev/null || echo 0)"
    if [[ $cols -gt 0 ]]; then
      width=$((cols < max ? cols : max))
      width=$((width > min ? width : min))
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

hr() { _hr_colored "$BLUE"; }
hr_green() { _hr_colored "$GREEN"; }

# -----------------------------------------------------------------------------
# Box drawing with rounded corners
# -----------------------------------------------------------------------------
get_box_width() {
  local width
  width="$(_get_terminal_width "$BOX_TERM_MIN_WIDTH" "$BOX_TERM_MAX_WIDTH")"
  # Box is 2 chars narrower
  width=$((width - 2))
  width=$((width > BOX_MIN_WIDTH ? width : BOX_MIN_WIDTH))
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
  content_width=$((width - 4)) # 2 borders + 2 spaces

  local vlen
  vlen="$(visual_length "$content")"
  if [[ $vlen -gt $content_width ]]; then
    content="$(truncate_ellipsis "$content" "$content_width")"
    vlen="$(visual_length "$content")"
  fi

  # Pad with spaces so the right border aligns
  local pad=$((content_width - vlen))
  printf "%b%s%b %b%*s %b%s%b\n" "${DIM}${BLUE}" "$UI_BOX_V" "${NC}" "$content" "$pad" "" "${DIM}${BLUE}" "$UI_BOX_V" "${NC}"
}

box_sep() {
  local width
  width="$(get_box_width)"
  printf "%b\n" "${DIM}${BLUE}${UI_BOX_ML}$(printf '%*s' "$((width - 2))" '' | tr ' ' "$UI_BOX_H")${UI_BOX_MR}${NC}"
}

box_title() {
  local title="$1"
  printf "%b\n" "${BOLD}${MAGENTA}${title}${NC}"
}

# -----------------------------------------------------------------------------
# String helpers
# -----------------------------------------------------------------------------

# Sanitize user-controlled text for safe printf %b output.
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
  if [[ -z $s || $max -le 0 ]]; then
    echo ""
    return 0
  fi
  local vlen
  vlen="$(visual_length "$s")"
  if [[ $vlen -le $max ]]; then
    echo "$s"
    return 0
  fi
  local ell="${UI_ELLIPSIS}"
  local ell_len="${#ell}"
  if [[ $max -le $ell_len ]]; then
    echo "${ell:0:max}"
    return 0
  fi
  # Strip ANSI before truncating to avoid cutting mid-sequence
  local plain
  plain="$(strip_ansi "$s")"
  echo "${plain:0:$((max - ell_len))}${ell}"
}

# Right align inside a given width
right_align() {
  local s="$1" width="$2"
  local len="${#s}"
  if [[ $len -ge $width ]]; then
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
pad_to_width() {
  local s="$1" target_width="$2"
  local vlen
  vlen="$(visual_length "$s")"
  if [[ $vlen -ge $target_width ]]; then
    printf '%b' "$s"
  else
    printf '%b%*s' "$s" $((target_width - vlen)) ""
  fi
}

# Color helper based on percentage thresholds (high = bad, e.g. time/tools)
color_by_pct() {
  local pct="$1" good="$2" warn="$3"
  if [[ $pct -lt $good ]]; then
    printf "%b" "${GREEN}"
  elif [[ $pct -lt $warn ]]; then
    printf "%b" "${YELLOW}"
  else
    printf "%b" "${RED}"
  fi
}

# Inverted color helper (high = good, e.g. health percentage)
color_by_pct_inverted() {
  local pct="$1"
  if [[ $pct -ge 80 ]]; then
    printf "%b" "${GREEN}"
  elif [[ $pct -ge 50 ]]; then
    printf "%b" "${YELLOW}"
  else
    printf "%b" "${RED}"
  fi
}

# Format number with thousands separators (1234567 -> 1,234,567)
fmt_thousands() {
  local n="$1"
  if [[ ${#n} -le 3 ]]; then
    printf '%s' "$n"
    return
  fi
  local result="" count=0 i
  for ((i = ${#n} - 1; i >= 0; i--)); do
    if [[ $count -gt 0 && $((count % 3)) -eq 0 ]]; then
      result=",${result}"
    fi
    result="${n:i:1}${result}"
    count=$((count + 1))
  done
  printf '%s' "$result"
}

# Relative time display (epoch -> "2m ago", "1h ago")
fmt_relative_time() {
  local epoch="$1"
  local now
  now="$(date '+%s')"
  local diff=$((now - epoch))
  if [[ $diff -lt 60 ]]; then
    printf '%ds ago' "$diff"
  elif [[ $diff -lt 3600 ]]; then
    printf '%dm ago' $((diff / 60))
  elif [[ $diff -lt 86400 ]]; then
    printf '%dh ago' $((diff / 3600))
  else
    printf '%dd ago' $((diff / 86400))
  fi
}

# -----------------------------------------------------------------------------
# Spinner
# -----------------------------------------------------------------------------
get_spinner_frame() {
  local tick="${1:-$SPINNER_TICK}"
  if [[ $UI_USE_ASCII == "true" ]]; then
    local count=${#SPINNER_FRAMES_ASCII[@]}
    printf '%s' "${SPINNER_FRAMES_ASCII[$((tick % count))]}"
  else
    local count=${#SPINNER_FRAMES_UNICODE[@]}
    printf '%s' "${SPINNER_FRAMES_UNICODE[$((tick % count))]}"
  fi
}

advance_spinner() {
  SPINNER_TICK=$((SPINNER_TICK + 1))
}

# -----------------------------------------------------------------------------
# Progress bar
# -----------------------------------------------------------------------------
# render_progress_bar current max width
# Renders: [########............] with color based on percentage
render_progress_bar() {
  local current="$1" max="$2" width="${3:-20}"
  local fill_char empty_char
  if [[ $UI_USE_ASCII == "true" ]]; then
    fill_char="$PROGRESS_FILL_ASCII"
    empty_char="$PROGRESS_EMPTY_ASCII"
  else
    fill_char="$PROGRESS_FILL_UNICODE"
    empty_char="$PROGRESS_EMPTY_UNICODE"
  fi

  local pct=0
  if [[ $max -gt 0 ]]; then
    pct=$(((current * 100) / max))
    [[ $pct -gt 100 ]] && pct=100
  fi

  local filled=$(((pct * width) / 100))
  local empty=$((width - filled))

  local color
  color="$(color_by_pct "$pct" 60 85)"
  local fill_str="" empty_str="" i
  for ((i = 0; i < filled; i++)); do fill_str+="$fill_char"; done
  for ((i = 0; i < empty; i++)); do empty_str+="$empty_char"; done

  printf '[%b%s%b%b%s%b]' "$color" "$fill_str" "$NC" "$DIM" "$empty_str" "$NC"
}

# Compact progress bar (no brackets, for inline use)
# Optional 4th arg: "inverted" to use inverted color scale (high=good)
render_progress_bar_compact() {
  local current="$1" max="$2" width="${3:-15}" color_mode="${4:-normal}"
  local fill_char empty_char
  if [[ $UI_USE_ASCII == "true" ]]; then
    fill_char="$PROGRESS_FILL_ASCII"
    empty_char="$PROGRESS_EMPTY_ASCII"
  else
    fill_char="$PROGRESS_FILL_UNICODE"
    empty_char="$PROGRESS_EMPTY_UNICODE"
  fi

  local pct=0
  if [[ $max -gt 0 ]]; then
    pct=$(((current * 100) / max))
    [[ $pct -gt 100 ]] && pct=100
  fi

  local filled=$(((pct * width) / 100))
  local empty=$((width - filled))

  local color
  if [[ $color_mode == "inverted" ]]; then
    color="$(color_by_pct_inverted "$pct")"
  else
    color="$(color_by_pct "$pct" 60 85)"
  fi
  local fill_str="" empty_str="" i
  for ((i = 0; i < filled; i++)); do fill_str+="$fill_char"; done
  for ((i = 0; i < empty; i++)); do empty_str+="$empty_char"; done

  printf '%b%s%b%b%s%b' "$color" "$fill_str" "$NC" "$DIM" "$empty_str" "$NC"
}

# -----------------------------------------------------------------------------
# Iteration history trail
# -----------------------------------------------------------------------------
record_iteration_result() {
  local status="$1"
  ITERATION_HISTORY+=("$status")
  if [[ ${#ITERATION_HISTORY[@]} -gt $HISTORY_MAX ]]; then
    ITERATION_HISTORY=("${ITERATION_HISTORY[@]:1}")
  fi
}

render_history_trail() {
  if [[ ${#ITERATION_HISTORY[@]} -eq 0 ]]; then
    return
  fi
  local sym_ok sym_fail sym_empty sym_info
  if [[ $UI_USE_ASCII == "true" ]]; then
    sym_ok="$HISTORY_OK_ASCII"
    sym_fail="$HISTORY_FAIL_ASCII"
    sym_empty="$HISTORY_EMPTY_ASCII"
    sym_info="$HISTORY_INFO_ASCII"
  else
    sym_ok="$HISTORY_OK_UNICODE"
    sym_fail="$HISTORY_FAIL_UNICODE"
    sym_empty="$HISTORY_EMPTY_UNICODE"
    sym_info="$HISTORY_INFO_UNICODE"
  fi
  local trail="" s
  for s in "${ITERATION_HISTORY[@]}"; do
    case "$s" in
      OK) trail+="${GREEN}${sym_ok}${NC}" ;;
      FAIL) trail+="${RED}${sym_fail}${NC}" ;;
      EMPTY) trail+="${YELLOW}${sym_empty}${NC}" ;;
      *) trail+="${DIM}${sym_info}${NC}" ;;
    esac
  done
  printf '%b' "$trail"
}

# Serialize history to comma-separated string (for cross-process sharing)
serialize_history() {
  local IFS=","
  printf '%s' "${ITERATION_HISTORY[*]}"
}

# Deserialize history from comma-separated string
deserialize_history() {
  local data="$1"
  [[ -z $data ]] && return
  IFS=',' read -ra ITERATION_HISTORY <<<"$data"
}

# -----------------------------------------------------------------------------
# Health & rate helpers
# -----------------------------------------------------------------------------

# Health pct: completed / (completed + failed) * 100
compute_health_pct() {
  local completed="$1" failed="$2"
  local total=$((completed + failed))
  if [[ $total -eq 0 ]]; then
    echo 100
    return
  fi
  echo $(((completed * 100) / total))
}

# Tasks per hour rate
compute_rate() {
  local completed="$1" elapsed_sec="$2"
  if [[ $elapsed_sec -lt 60 || $completed -eq 0 ]]; then
    printf '%s' "—"
    return
  fi
  local rate_x10=$((completed * 36000 / elapsed_sec))
  local whole=$((rate_x10 / 10))
  local frac=$((rate_x10 % 10))
  printf '%d.%d/hr' "$whole" "$frac"
}

# Pull last N "signal" lines from output file for quick diagnostics
tail_signal_lines() {
  local file="$1" n="${2:-6}"
  [[ -f $file ]] || return 0
  grep -E "^(PICKING|WRITING|TESTING|PASSED|MARKING|DONE|REMAINING|EXIT_SIGNAL|ATTEMPT_FAILED|>>> )" -- "$file" 2>/dev/null \
    | tail -n "$n" || true
}

# Apply consistent color formatting to a signal line (for Signals sections)
colorize_signal_line() {
  local line="$1"
  if [[ $line == ">>> "* ]]; then
    printf '%b' "${DIM}${line}${NC}"
  elif [[ $line == "PICKING:"* ]]; then
    printf '%b' "${BOLD}${ORANGE}${line}${NC}"
  elif [[ $line == "DONE:"* || $line == "MARKING"* ]]; then
    printf '%b' "${BOLD}${GREEN}${line}${NC}"
  elif [[ $line == "REMAINING:"* ]]; then
    printf '%b' "${DIM}${line}${NC}"
  elif [[ $line == "ATTEMPT_FAILED:"* ]]; then
    printf '%b' "${BOLD}${RED}${line}${NC}"
  elif [[ $line == "EXIT_SIGNAL:"* ]]; then
    printf '%b' "${BOLD}${CYAN}${line}${NC}"
  else
    printf '%b' "${DIM}${line}${NC}"
  fi
}

# -----------------------------------------------------------------------------
# Animated wait countdown with keyboard shortcuts (TTY only)
# -----------------------------------------------------------------------------
wait_with_countdown() {
  local seconds="$1"
  local i
  if [[ ${WAIT_COUNTDOWN:-true} != "true" || ${QUIET:-false} == "true" || ! -t 1 ]]; then
    sleep "$seconds"
    return 0
  fi

  for ((i = seconds; i > 0; i--)); do
    printf "\r%b\033[K" "${BLUE}T${NC}  Next in ${YELLOW}${i}s${NC}"
    sleep 1
  done
  printf "\r\033[K"
}

# -----------------------------------------------------------------------------
# Dynamic banner — printed as normal scrolling output (no cursor tricks)
# Renders exactly BANNER_LINES lines: box_top + 4 content + box_bottom
# -----------------------------------------------------------------------------

# shellcheck disable=SC2034
BANNER_LINES=6

# No-op stubs — scroll regions removed for reliability.
reset_scroll_region() { :; }
reapply_scroll_region() { :; }

# Compact inline status line (called periodically by the monitor).
# Overwrites in-place via \r\033[K so progress bars animate.
print_status_line() {
  is_tty || return 0
  local elapsed_sec="$1" iter_timeout="$2"
  local tool_count="$3" max_tools="$4"
  local picked_task="$5"

  local task_display="" picked_safe=""
  if [[ -n $picked_task ]]; then
    picked_safe="$(sanitize_tty_text "$picked_task")"
    task_display=" ${DIM}|${NC} $(truncate_ellipsis "$picked_safe" "$STATUS_TASK_MAX")"
  fi

  local spinner
  spinner="$(get_spinner_frame "$SPINNER_TICK")"
  advance_spinner

  local time_bar tools_bar
  time_bar="$(render_progress_bar_compact "$elapsed_sec" "$iter_timeout" 12)"
  tools_bar="$(render_progress_bar_compact "$tool_count" "$max_tools" 8)"

  # \r goes to start of line, \033[K clears to end — overwrites previous status
  printf "\r\033[K  %b" "${CYAN}${spinner}${NC} ${time_bar} ${DIM}${elapsed_sec}s/${iter_timeout}s${NC} ${tools_bar} ${DIM}#${tool_count}/${max_tools}${NC}${task_display}"
}

# Push past an in-place status line before printing engine output.
# Called from _process_line in engine.sh so engine text appears on its own line.
clear_status_line() {
  printf "\r\033[K"
}

# Render the dynamic banner
render_dynamic_banner() {
  local iteration="$1"
  local time_short="$2" # used for display context, kept for API compat
  local quote="$3"
  local state_label="$4"
  local completed="$5" failed="$6" skipped="$7"
  local elapsed_sec="$8" iter_timeout="$9"
  local tool_count="${10}" max_tools="${11}"
  local picked_task="${12:-}"
  local attempt_info="${13:-}"
  local run_elapsed="${14:-0}"

  # State badge color
  local badge_color="$BLUE"
  case "$state_label" in
    OK | COMPLETED | SUCCESS) badge_color="$GREEN" ;;
    FAIL | FAILED | ERROR | TIMEOUT) badge_color="$RED" ;;
    EMPTY | WARN) badge_color="$YELLOW" ;;
  esac

  # Task slot
  local task_slot="" picked_safe=""
  if [[ -n $picked_task ]]; then
    picked_safe="$(sanitize_tty_text "$picked_task")"
    task_slot="$(truncate_ellipsis "$picked_safe" "$BANNER_TASK_MAX")"
  fi

  # Spinner for RUNNING state
  local spinner_display=""
  if [[ $state_label == "RUNNING" ]]; then
    spinner_display="$(get_spinner_frame) "
  fi

  # Line 1: Iter + Task + State (+ attempt info)
  local line1
  if [[ -n $task_slot ]]; then
    line1="${BOLD}${CYAN}#${iteration}${NC} ${DIM}|${NC} ${WHITE}${task_slot}${NC}"
    if [[ -n $attempt_info ]]; then
      line1+=" ${DIM}(${attempt_info})${NC}"
    fi
    line1+=" ${DIM}|${NC} ${spinner_display}${BOLD}${badge_color}${state_label}${NC}"
  else
    line1="${BOLD}${CYAN}#${iteration}${NC} ${DIM}|${NC} ${spinner_display}${BOLD}${badge_color}${state_label}${NC}"
  fi

  # Line 2: Counters + elapsed + tools
  local line2
  line2="${GREEN}C${completed}${NC} ${RED}F${failed}${NC} ${YELLOW}S${skipped}${NC} ${DIM}|${NC} ${DIM}${elapsed_sec}s/${iter_timeout}s${NC} ${DIM}|${NC} ${DIM}tools${NC} ${tool_count}/${max_tools}"

  # Line 3: Health + rate + history
  local health_pct rate_display history_display=""
  health_pct="$(compute_health_pct "$completed" "$failed")"
  if [[ $run_elapsed -gt 0 ]]; then
    rate_display="$(compute_rate "$completed" "$run_elapsed")"
  else
    rate_display="—"
  fi
  if [[ ${#ITERATION_HISTORY[@]} -gt 0 ]]; then
    history_display=" ${DIM}|${NC} $(render_history_trail)"
  fi
  local line3="${DIM}Health${NC} ${health_pct}% ${DIM}|${NC} ${DIM}Rate${NC} ${CYAN}${rate_display}${NC}${history_display}"

  # Line 4: Quote or empty for fixed height
  local line4=""
  if [[ -n $quote ]]; then
    line4="${DIM}${MAGENTA}\"${quote}\"${NC}"
  fi

  box_top
  box_line "$line1"
  box_line "$line2"
  box_line "$line3"
  box_line "$line4"
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
      printf "  %b\n" "${GREEN}${UI_SYM_OK}${NC}  Completed ${WHITE}${task_safe}${NC} in ${CYAN}${iter_elapsed_fmt}${NC} ${DIM}(${tool_count} tool calls)${NC}"
      ;;
    FAIL)
      printf "  %b\n" "${RED}${UI_SYM_FAIL}${NC}  Failed ${WHITE}${task_safe}${NC} after ${CYAN}${iter_elapsed_fmt}${NC}: ${RED}${failure_safe}${NC}"
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
# Error context box (structured failure display)
# -----------------------------------------------------------------------------
print_error_context_box() {
  local task="$1"
  local reason="$2"
  local attempt_info="$3"
  local output_file="$4"

  local task_safe reason_safe
  task_safe="$(sanitize_tty_text "$task")"
  reason_safe="$(sanitize_tty_text "$reason")"

  local width
  width="$(get_box_width)"
  local title_text=" FAILURE DETAILS "
  local title_len=${#title_text}
  local remaining=$((width - 2 - title_len - 2))
  [[ $remaining -lt 1 ]] && remaining=1

  echo ""
  printf "%b\n" "${DIM}${BLUE}${UI_BOX_TL}${UI_BOX_H}${NC} ${RED}${BOLD}FAILURE DETAILS${NC} ${DIM}${BLUE}$(printf '%*s' "$remaining" '' | tr ' ' "$UI_BOX_H")${UI_BOX_TR}${NC}"

  local inner=$((width - 4))

  box_line "${DIM}Task:${NC}    ${WHITE}$(truncate_ellipsis "$task_safe" $((inner - 10)))${NC}"
  box_line "${DIM}Reason:${NC}  ${RED}$(truncate_ellipsis "$reason_safe" $((inner - 10)))${NC}"
  if [[ -n $attempt_info ]]; then
    box_line "${DIM}Attempt:${NC} ${YELLOW}${attempt_info}${NC}"
  fi

  if [[ -n $output_file && -f $output_file ]]; then
    local lines
    lines="$(tail_signal_lines "$output_file" 5)"
    if [[ -n $lines ]]; then
      box_sep
      box_line "${DIM}Signals:${NC}"
      while IFS= read -r l; do
        local line_safe
        line_safe="$(sanitize_tty_text "$l")"
        box_line "  $(colorize_signal_line "$line_safe")"
      done <<<"$lines"
    fi
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
  local attempt_info="${15:-}"

  local task_safe failure_safe
  task_safe="$(sanitize_tty_text "$task_display")"
  failure_safe="$(sanitize_tty_text "$failure_reason")"

  # For failures, show structured error context box
  if [[ $status == "FAIL" && -n $failure_reason ]]; then
    print_error_context_box "$task_display" "$failure_reason" "$attempt_info" "$output_file"
    return
  fi

  echo ""
  hr

  case "$status" in
    OK)
      printf "  %b\n" "${GREEN}${UI_SYM_OK}${NC}  Completed ${WHITE}${task_safe}${NC} in ${CYAN}${iter_elapsed_fmt}${NC} ${DIM}(${tool_count} tool calls)${NC}"
      ;;
    EMPTY)
      printf "  %b\n" "${YELLOW}!${NC}  Empty iteration ${DIM}(no tools, no changes, no task picked)${NC}"
      ;;
    *)
      printf "  %b\n" "${BLUE}i${NC}  Iteration finished in ${CYAN}${iter_elapsed_fmt}${NC}"
      ;;
  esac

  # Detailed metrics (dimmed)
  printf "  %b\n" "${DIM}tools=${tool_count}/${max_tools}  files_changed=${files_changed}  jq=${jq_exit}  claude=${claude_exit}${NC}"
  printf "  %b\n" "${DIM}picked=${picked_yes} done=${done_yes} exit=${exit_yes} attempt_failed=${explicit_fail_yes}${NC}"

  # Signal trail
  local lines
  lines="$(tail_signal_lines "$output_file" 6)"
  if [[ -n $lines ]]; then
    echo ""
    printf "  %b\n" "${DIM}Signals:${NC}"
    local line_safe
    while IFS= read -r l; do
      line_safe="$(sanitize_tty_text "$l")"
      printf "    %b\n" "$(colorize_signal_line "$line_safe")"
    done <<<"$lines"
  fi
  hr
}

# -----------------------------------------------------------------------------
# OS notifications
# -----------------------------------------------------------------------------
notify() {
  [[ ${ENABLE_NOTIFY:-false} == "true" ]] || return 0
  local title="$1" message="$2"

  # macOS
  if command -v osascript >/dev/null 2>&1; then
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null &
    return 0
  fi
  # Linux
  if command -v notify-send >/dev/null 2>&1; then
    notify-send "$title" "$message" 2>/dev/null &
    return 0
  fi
  # tmux
  if [[ -n ${TMUX:-} ]] && command -v tmux >/dev/null 2>&1; then
    tmux display-message "$title: $message" 2>/dev/null &
    return 0
  fi
}

# -----------------------------------------------------------------------------
# Structured JSONL event logging
# -----------------------------------------------------------------------------
RALPH_LOG_SCHEMA_VERSION=1

log_event_jsonl() {
  [[ ${LOG_FORMAT:-text} == "jsonl" && -n ${LOG_FILE:-} ]] || return 0
  local event="$1"
  shift
  local ts
  ts="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')"

  # Build jq args for safe JSON encoding
  local -a jq_args=(
    --arg ts "$ts"
    --arg event "$event"
    --argjson schema_version "$RALPH_LOG_SCHEMA_VERSION"
    --arg run_id "${RUN_ID:-}"
    --arg engine "${ENGINE:-}"
  )
  # shellcheck disable=SC2016  # Dollar signs are jq variable references, not shell
  local jq_expr='{ts: $ts, event: $event, schema_version: $schema_version, run_id: $run_id, engine: $engine'

  if [[ -n ${WORKER_ID:-} && ${WORKER_ID:-0} -gt 0 ]]; then
    jq_args+=(--argjson worker_id "$WORKER_ID")
    # shellcheck disable=SC2016
    jq_expr+=', worker_id: $worker_id'
  fi

  # Add extra key/value pairs
  while [[ $# -ge 2 ]]; do
    local key="$1" val="$2"
    shift 2
    if [[ $val =~ ^[0-9]+$ ]]; then
      jq_args+=(--argjson "$key" "$val")
    else
      jq_args+=(--arg "$key" "$val")
    fi
    # Use quoted key in jq expression: ("key"): $key
    jq_expr+=", (\"$key\"): \$$key"
  done
  jq_expr+='}'

  jq -n -c "${jq_args[@]}" "$jq_expr" >>"$LOG_FILE"
}

# -----------------------------------------------------------------------------
# Smarter terminal title (with state summary)
# -----------------------------------------------------------------------------
set_smart_title() {
  [[ ${ENABLE_TITLE:-true} == "true" ]] || return 0
  is_tty || return 0
  local state="$1"
  local iteration="${2:-}"
  local completed="${3:-0}"
  local failed="${4:-0}"
  local task="${5:-}"

  local title="Ralph"
  if [[ -n $iteration ]]; then
    title+=" ${UI_SYM_OK}${completed} ${UI_SYM_FAIL}${failed} | #${iteration}"
  fi

  case "$state" in
    running)
      if [[ -n $task ]]; then
        title+=" ${task:0:25}"
      else
        title+=" running"
      fi
      ;;
    idle) title+=" | idle" ;;
    complete) title+=" | all done" ;;
    *) title+=" | ${state}" ;;
  esac

  printf "\033]0;%s\007" "$title"
  # iTerm2 badge (OSC 1337)
  if [[ ${TERM_PROGRAM:-} == "iTerm.app" ]]; then
    printf "\033]1337;SetBadge=%s\007" "$(printf '%s' "$title" | base64)"
  fi
}

# Clear iTerm2 badge
clear_iterm_badge() {
  if [[ ${TERM_PROGRAM:-} == "iTerm.app" ]] && is_tty; then
    printf "\033]1337;SetBadge=\007"
  fi
}

# -----------------------------------------------------------------------------
# Worker status panel
# -----------------------------------------------------------------------------
render_worker_panel() {
  [[ ${NUM_WORKERS:-1} -gt 1 ]] || return 0
  [[ -n ${WORKER_STATE_DIR:-} && -d ${WORKER_STATE_DIR:-} ]] || return 0

  echo ""
  printf "  %b\n" "${BOLD}Workers${NC}"
  local i
  for i in $(seq 1 "$NUM_WORKERS"); do
    local line="" wcc=0 wff=0
    local counters_file="${WORKER_STATE_DIR}/w${i}.counters"
    if [[ -f $counters_file ]]; then
      IFS= read -r line <"$counters_file" 2>/dev/null || true
      if [[ $line =~ ^COMPLETED=([0-9]+)[[:space:]]+FAILED=([0-9]+) ]]; then
        wcc="${BASH_REMATCH[1]}"
        wff="${BASH_REMATCH[2]}"
      fi
    fi

    local task="(idle)" status_color="$DIM" status_label="IDLE"
    if [[ -f ${CLAIMS_FILE:-} ]]; then
      local claim_line
      claim_line="$(grep "^W${i}|" "${CLAIMS_FILE}" 2>/dev/null | tail -1 || true)"
      if [[ -n $claim_line ]]; then
        local encoded_task
        encoded_task="$(echo "$claim_line" | awk -F'|' '{print $NF}')"
        if [[ -n $encoded_task ]]; then
          task="$(decode_claim_task "$encoded_task" 2>/dev/null || echo "?")"
          task="$(truncate_ellipsis "$(sanitize_tty_text "$task")" 25)"
          status_color="$GREEN"
          status_label="RUN"
        fi
      fi
    fi

    # Check if worker is still alive
    local wpid_idx=$((i - 1))
    if [[ -n ${WORKER_PIDS[$wpid_idx]:-} ]]; then
      if ! kill -0 "${WORKER_PIDS[$wpid_idx]}" 2>/dev/null; then
        status_color="$DIM"
        status_label="DONE"
        task="—"
      fi
    fi

    printf "  %b %-4b %b %b %b\n" \
      "${CYAN}W${i}${NC}" \
      "${status_color}${status_label}${NC}" \
      "${GREEN}${UI_SYM_OK}${wcc}${NC}" \
      "${RED}${UI_SYM_FAIL}${wff}${NC}" \
      "${DIM}${task}${NC}"
  done
}

# -----------------------------------------------------------------------------
# Dashboard mode
# -----------------------------------------------------------------------------
DASHBOARD_STATE_FILE=""

setup_dashboard() {
  [[ ${UI_MODE:-full} == "dashboard" ]] || return 0
  DASHBOARD_STATE_FILE="$(mktemp "${TMPDIR:-/tmp}/ralph_dashboard.XXXXXX")"
  if is_tty; then
    tput smcup 2>/dev/null || printf "\033[?1049h" # enter alternate screen buffer
    tput civis 2>/dev/null || true                 # hide cursor
    printf "\033[2J"                               # clear
    printf "\033[H"                                # home
  fi
}

cleanup_dashboard() {
  [[ ${UI_MODE:-full} == "dashboard" ]] || return 0
  if is_tty; then
    tput cnorm 2>/dev/null || true                 # show cursor
    tput rmcup 2>/dev/null || printf "\033[?1049l" # leave alternate screen buffer
  fi
  if [[ -n ${DASHBOARD_STATE_FILE:-} ]]; then
    rm -f "$DASHBOARD_STATE_FILE" 2>/dev/null || true
  fi
}

# Write current state for dashboard renderer
write_dashboard_state() {
  [[ -n ${DASHBOARD_STATE_FILE:-} ]] || return 0
  local iteration="$1" state="$2" task="$3"
  local completed="$4" failed="$5" skipped="$6"
  local elapsed="$7" timeout="$8"
  local tools="$9" max_tools="${10}"
  local quote="${11:-}" run_elapsed="${12:-0}"
  cat >"$DASHBOARD_STATE_FILE" <<EOF
ITERATION=${iteration}
STATE=${state}
TASK=${task}
COMPLETED=${completed}
FAILED=${failed}
SKIPPED=${skipped}
ELAPSED=${elapsed}
TIMEOUT=${timeout}
TOOLS=${tools}
MAX_TOOLS=${max_tools}
QUOTE=${quote}
HISTORY=$(serialize_history)
RUN_ELAPSED=${run_elapsed}
EOF
}

# Read dashboard state from file (sets _DASH_* variables)
read_dashboard_state() {
  [[ -n ${DASHBOARD_STATE_FILE:-} && -f ${DASHBOARD_STATE_FILE:-} ]] || return 1
  while IFS='=' read -r key val; do
    case "$key" in
      ITERATION) _DASH_ITERATION="$val" ;;
      STATE) _DASH_STATE="$val" ;;
      TASK) _DASH_TASK="$val" ;;
      COMPLETED) _DASH_COMPLETED="$val" ;;
      FAILED) _DASH_FAILED="$val" ;;
      SKIPPED) _DASH_SKIPPED="$val" ;;
      ELAPSED) _DASH_ELAPSED="$val" ;;
      TIMEOUT) _DASH_TIMEOUT="$val" ;;
      TOOLS) _DASH_TOOLS="$val" ;;
      MAX_TOOLS) _DASH_MAX_TOOLS="$val" ;;
      QUOTE) _DASH_QUOTE="$val" ;;
      HISTORY) _DASH_HISTORY="$val" ;;
      RUN_ELAPSED) _DASH_RUN_ELAPSED="$val" ;;
    esac
  done <"$DASHBOARD_STATE_FILE"
}

# Render the full dashboard (clears screen and redraws)
render_dashboard() {
  is_tty || return 0
  local raw_jsonl="${1:-}" output_file="${2:-}" iter_started="${3:-0}"

  # Defaults
  _DASH_ITERATION="${_DASH_ITERATION:-1}"
  _DASH_STATE="${_DASH_STATE:-IDLE}"
  _DASH_TASK="${_DASH_TASK:-}"
  _DASH_COMPLETED="${_DASH_COMPLETED:-0}"
  _DASH_FAILED="${_DASH_FAILED:-0}"
  _DASH_SKIPPED="${_DASH_SKIPPED:-0}"
  _DASH_ELAPSED="${_DASH_ELAPSED:-0}"
  _DASH_TIMEOUT="${_DASH_TIMEOUT:-600}"
  _DASH_TOOLS="${_DASH_TOOLS:-0}"
  _DASH_MAX_TOOLS="${_DASH_MAX_TOOLS:-50}"
  _DASH_QUOTE="${_DASH_QUOTE:-}"
  _DASH_HISTORY="${_DASH_HISTORY:-}"
  _DASH_RUN_ELAPSED="${_DASH_RUN_ELAPSED:-0}"

  read_dashboard_state 2>/dev/null || true

  # Override with live data if available
  if [[ -n $raw_jsonl && -f $raw_jsonl && $iter_started -gt 0 ]]; then
    local _now
    _now="$(date '+%s')"
    _DASH_ELAPSED=$((_now - iter_started))
    if [[ ${ENGINE:-claude} == "codex" ]]; then
      _DASH_TOOLS="$(count_tool_calls_from_codex_jsonl "$raw_jsonl" 2>/dev/null || echo 0)"
    else
      _DASH_TOOLS="$(count_tool_calls_from_jsonl "$raw_jsonl" 2>/dev/null || echo 0)"
    fi
    [[ -z $_DASH_TOOLS ]] && _DASH_TOOLS=0
  fi

  if [[ -n $output_file && -f $output_file ]]; then
    local picked
    picked="$(grep 'PICKING: ' "$output_file" 2>/dev/null | sed 's/.*PICKING: //' | head -1 || true)"
    [[ -n $picked ]] && _DASH_TASK="$picked"
  fi

  # Deserialize history
  if [[ -n $_DASH_HISTORY ]]; then
    deserialize_history "$_DASH_HISTORY"
  fi

  # Derived values
  local health_pct rate_display
  health_pct="$(compute_health_pct "$_DASH_COMPLETED" "$_DASH_FAILED")"
  rate_display="$(compute_rate "$_DASH_COMPLETED" "$_DASH_RUN_ELAPSED")"

  local spinner badge_color
  spinner="$(get_spinner_frame "$SPINNER_TICK")"
  advance_spinner

  badge_color="$BLUE"
  case "$_DASH_STATE" in
    OK | COMPLETED | SUCCESS) badge_color="$GREEN" ;;
    FAIL | FAILED | ERROR | TIMEOUT) badge_color="$RED" ;;
    EMPTY | WARN) badge_color="$YELLOW" ;;
  esac

  # -- Render into buffer for flicker-free output --
  local _frame
  _frame="$(
    box_top
    box_line "${BOLD}${BLUE}RALPH LOOP${NC}                              ${DIM}Run: ${CYAN}${RUN_ID:-?}${NC}"
    box_sep

    # Iteration + state
    local task_safe=""
    if [[ -n $_DASH_TASK ]]; then
      task_safe="$(truncate_ellipsis "$(sanitize_tty_text "$_DASH_TASK")" 35)"
    fi
    if [[ $_DASH_STATE == "RUNNING" ]]; then
      box_line "${BOLD}${CYAN}Iteration #${_DASH_ITERATION}${NC}  ${CYAN}${spinner}${NC} ${BOLD}${badge_color}${_DASH_STATE}${NC}"
    else
      box_line "${BOLD}${CYAN}Iteration #${_DASH_ITERATION}${NC}  ${BOLD}${badge_color}${_DASH_STATE}${NC}"
    fi
    if [[ -n $task_safe ]]; then
      box_line "${DIM}Task:${NC} ${WHITE}${task_safe}${NC}"
    fi

    box_line ""

    # Progress bars
    local time_bar tools_bar time_pct=0 tools_pct=0
    time_bar="$(render_progress_bar "$_DASH_ELAPSED" "$_DASH_TIMEOUT" 20)"
    tools_bar="$(render_progress_bar "$_DASH_TOOLS" "$_DASH_MAX_TOOLS" 20)"
    if [[ $_DASH_TIMEOUT -gt 0 ]]; then
      time_pct=$(((_DASH_ELAPSED * 100) / _DASH_TIMEOUT))
      [[ $time_pct -gt 100 ]] && time_pct=100
    fi
    if [[ $_DASH_MAX_TOOLS -gt 0 ]]; then
      tools_pct=$(((_DASH_TOOLS * 100) / _DASH_MAX_TOOLS))
      [[ $tools_pct -gt 100 ]] && tools_pct=100
    fi
    box_line "${DIM}Time ${NC} ${time_bar} ${DIM}${time_pct}%  ${_DASH_ELAPSED}s/${_DASH_TIMEOUT}s${NC}"
    box_line "${DIM}Tools${NC} ${tools_bar} ${DIM}${tools_pct}%  ${_DASH_TOOLS}/${_DASH_MAX_TOOLS}${NC}"
    box_line ""

    # Counters + health + rate
    local health_bar
    health_bar="$(render_progress_bar_compact "$health_pct" 100 10 inverted)"
    box_line "${GREEN}${UI_SYM_OK} ${_DASH_COMPLETED} completed${NC}   ${RED}${UI_SYM_FAIL} ${_DASH_FAILED} failed${NC}   ${YELLOW}${UI_SYM_SKIP} ${_DASH_SKIPPED} skipped${NC}"
    box_line "${DIM}Rate:${NC} ${CYAN}${rate_display}${NC}   ${DIM}Health:${NC} ${health_bar} ${DIM}${health_pct}%${NC}"

    # History trail
    if [[ ${#ITERATION_HISTORY[@]} -gt 0 ]]; then
      box_line ""
      box_line "${DIM}History:${NC} $(render_history_trail)"
    fi

    # Worker panel (parallel mode)
    if [[ ${NUM_WORKERS:-1} -gt 1 && -n ${WORKER_STATE_DIR:-} && -d ${WORKER_STATE_DIR:-} ]]; then
      box_sep
      box_line "${BOLD}Workers${NC}"
      local i
      for i in $(seq 1 "$NUM_WORKERS"); do
        local wline="" wcc=0 wff=0
        local cf="${WORKER_STATE_DIR}/w${i}.counters"
        if [[ -f $cf ]]; then
          IFS= read -r wline <"$cf" 2>/dev/null || true
          if [[ $wline =~ ^COMPLETED=([0-9]+)[[:space:]]+FAILED=([0-9]+) ]]; then
            wcc="${BASH_REMATCH[1]}"
            wff="${BASH_REMATCH[2]}"
          fi
        fi
        local wtask="(idle)" wstatus="${DIM}IDLE${NC}"
        if [[ -f ${CLAIMS_FILE:-} ]]; then
          local cl
          cl="$(grep "^W${i}|" "${CLAIMS_FILE}" 2>/dev/null | tail -1 || true)"
          if [[ -n $cl ]]; then
            local enc
            enc="$(echo "$cl" | awk -F'|' '{print $NF}')"
            if [[ -n $enc ]]; then
              wtask="$(decode_claim_task "$enc" 2>/dev/null || echo "?")"
              wtask="$(truncate_ellipsis "$(sanitize_tty_text "$wtask")" 22)"
              wstatus="${GREEN}RUN${NC}"
            fi
          fi
        fi
        box_line "${CYAN}W${i}${NC} ${wstatus} ${GREEN}${UI_SYM_OK}${wcc}${NC} ${RED}${UI_SYM_FAIL}${wff}${NC} ${DIM}${wtask}${NC}"
      done
    fi

    # Recent output lines
    if [[ -n $output_file && -f $output_file ]]; then
      local recent
      recent="$(tail_signal_lines "$output_file" 3)"
      if [[ -n $recent ]]; then
        box_sep
        box_line "${DIM}Recent:${NC}"
        while IFS= read -r l; do
          local ls
          ls="$(sanitize_tty_text "$l")"
          box_line "  $(colorize_signal_line "$(truncate_ellipsis "$ls" 45)")"
        done <<<"$recent"
      fi
    fi

    # Quote
    if [[ -n $_DASH_QUOTE ]]; then
      box_line ""
      box_line "${DIM}${MAGENTA}\"${_DASH_QUOTE}\"${NC}"
    fi

    box_bottom
  )"

  # Single write: cursor home + frame + clear remaining lines
  is_tty && printf '\033[H%b\033[J' "$_frame"
}

# Dashboard countdown (replaces wait_with_countdown in dashboard mode)
dashboard_countdown() {
  local seconds="$1"
  local i
  for ((i = seconds; i > 0; i--)); do
    write_dashboard_state "${_DASH_ITERATION:-0}" "IDLE (${i}s)" "" \
      "${COMPLETED_COUNT:-0}" "${FAILED_COUNT:-0}" \
      "$(get_skipped_tasks 2>/dev/null | wc -l | tr -d ' ')" \
      "0" "${ITERATION_TIMEOUT:-600}" "0" "${MAX_TOOL_CALLS:-50}" "" \
      "$(($(date '+%s') - STARTED_EPOCH))"
    render_dashboard "" "" 0
    sleep 1
  done
}

# -----------------------------------------------------------------------------
# Run summary statistics
# -----------------------------------------------------------------------------
show_run_summary() {
  local now elapsed skipped_count
  now="$(date '+%s')"
  elapsed=$((now - STARTED_EPOCH))
  skipped_count="$(get_skipped_tasks | wc -l | tr -d ' ')"

  # Restore normal screen if dashboard was active
  cleanup_dashboard
  clear_iterm_badge

  local health_pct rate_display
  health_pct="$(compute_health_pct "$COMPLETED_COUNT" "$FAILED_COUNT")"
  rate_display="$(compute_rate "$COMPLETED_COUNT" "$elapsed")"

  echo ""
  hr
  printf "%b\n" "${BOLD}${BLUE}Run Summary${NC}"
  printf "  %-16s %b\n" "Run ID:" "${CYAN}${RUN_ID}${NC}"
  printf "  %-16s %b\n" "Duration:" "${CYAN}$(fmt_hms "$elapsed")${NC}"
  printf "  %-16s %b\n" "Iterations:" "${CYAN}${ITERATION_COUNT}${NC}"
  printf "  %-16s %b\n" "Completed:" "${GREEN}${COMPLETED_COUNT}${NC}"
  printf "  %-16s %b\n" "Failed:" "${RED}${FAILED_COUNT}${NC}"
  printf "  %-16s %b\n" "Skipped:" "${YELLOW}${skipped_count}${NC}"
  printf "  %-16s %b\n" "Rate:" "${CYAN}${rate_display}${NC}"

  local health_bar
  health_bar="$(render_progress_bar_compact "$health_pct" 100 10 inverted)"
  printf "  %-16s %b %b\n" "Health:" "$health_bar" "${DIM}${health_pct}%${NC}"

  if [[ ${#ITERATION_HISTORY[@]} -gt 0 ]]; then
    local trail
    trail="$(render_history_trail)"
    printf "  %-16s %b %b\n" "History:" "$trail" "${DIM}(${#ITERATION_HISTORY[@]} iterations)${NC}"
  fi
  hr

  # JSONL summary event
  log_event_jsonl "run_end" \
    "run_id" "$RUN_ID" \
    "duration" "$elapsed" \
    "iterations" "$ITERATION_COUNT" \
    "completed" "$COMPLETED_COUNT" \
    "failed" "$FAILED_COUNT" \
    "skipped" "$skipped_count" \
    "health" "$health_pct"

  notify "Ralph Loop" "Run complete: ${COMPLETED_COUNT} done, ${FAILED_COUNT} failed in $(fmt_hms "$elapsed")"
}
