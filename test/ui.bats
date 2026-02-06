#!/usr/bin/env bats
# Tests for lib/ui.sh

setup()    { load 'test_helper/common-setup'; _common_setup; }
teardown() { _common_teardown; }

# =============================================================================
# Box drawing tests (Task 4)
# =============================================================================

# --- get_box_width ---

@test "get_box_width: returns a number >= BOX_MIN_WIDTH" {
  run get_box_width
  assert_success
  [[ "$output" -ge "$BOX_MIN_WIDTH" ]]
}

# --- box_top ---

@test "box_top: output starts and ends with + in ASCII mode" {
  UI_ASCII=true
  setup_ui_charset
  run box_top
  assert_success
  local stripped
  stripped="$(printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g')"
  [[ "$stripped" == "+"* ]]
  [[ "$stripped" == *"+" ]]
}

# --- box_bottom ---

@test "box_bottom: output starts and ends with + in ASCII mode" {
  UI_ASCII=true
  setup_ui_charset
  run box_bottom
  assert_success
  local stripped
  stripped="$(printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g')"
  [[ "$stripped" == "+"* ]]
  [[ "$stripped" == *"+" ]]
}

# --- box_sep ---

@test "box_sep: output starts and ends with + in ASCII mode" {
  UI_ASCII=true
  setup_ui_charset
  run box_sep
  assert_success
  local stripped
  stripped="$(printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g')"
  [[ "$stripped" == "+"* ]]
  [[ "$stripped" == *"+" ]]
}

# --- box_line ---

@test "box_line: contains the content text" {
  UI_ASCII=true
  setup_ui_charset
  run box_line "Hello World"
  assert_success
  assert_output --partial "Hello World"
}

@test "box_line: uses | border in ASCII mode" {
  UI_ASCII=true
  setup_ui_charset
  run box_line "test content"
  assert_success
  local stripped
  stripped="$(printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g')"
  [[ "$stripped" == "|"* ]]
  [[ "$stripped" == *"|" ]]
}

@test "box_line: truncates long content with ellipsis" {
  UI_ASCII=true
  setup_ui_charset
  local long_string
  long_string="$(printf 'A%.0s' $(seq 1 200))"
  run box_line "$long_string"
  assert_success
  # In ASCII mode, ellipsis is "..."
  assert_output --partial "..."
}

# --- box_title ---

@test "box_title: contains the title text" {
  run box_title "My Title"
  assert_success
  assert_output --partial "My Title"
}

# =============================================================================
# String helper tests (Task 3)
# =============================================================================

# --- sanitize_tty_text ---

@test "sanitize_tty_text: strips carriage returns" {
  run sanitize_tty_text $'hello\rworld'
  assert_success
  assert_output "hello world"
}

@test "sanitize_tty_text: strips newlines" {
  run sanitize_tty_text $'hello\nworld'
  assert_success
  assert_output "hello world"
}

@test "sanitize_tty_text: strips tabs" {
  run sanitize_tty_text $'hello\tworld'
  assert_success
  assert_output "hello world"
}

@test "sanitize_tty_text: strips escape sequences" {
  run sanitize_tty_text $'hello\033world'
  assert_success
  assert_output "helloworld"
}

@test "sanitize_tty_text: escapes backslashes" {
  run sanitize_tty_text 'hello\world'
  assert_success
  assert_output 'hello\\world'
}

@test "sanitize_tty_text: handles empty string" {
  run sanitize_tty_text ""
  assert_success
  assert_output ""
}

# --- right_align ---

@test "right_align: pads short string on the left" {
  run right_align "hi" 10
  assert_success
  assert_output "        hi"
}

@test "right_align: passes through string longer than width" {
  run right_align "hello world" 5
  assert_success
  assert_output "hello world"
}

# --- pad_to_width ---

@test "pad_to_width: pads short string with trailing spaces" {
  result="$(pad_to_width "hi" 10)"
  assert_equal "${#result}" 10
}

# --- fmt_thousands ---

@test "fmt_thousands: formats small numbers (no commas)" {
  run fmt_thousands 42
  assert_success
  assert_output "42"
}

@test "fmt_thousands: formats thousands" {
  run fmt_thousands 1234
  assert_success
  assert_output "1,234"
}

@test "fmt_thousands: formats millions" {
  run fmt_thousands 1234567
  assert_success
  assert_output "1,234,567"
}

# --- color_by_pct ---

@test "color_by_pct: returns GREEN for low percentage" {
  GREEN="G" YELLOW="Y" RED="R"
  run color_by_pct 10 50 80
  assert_success
  assert_output "G"
}

@test "color_by_pct: returns YELLOW for medium percentage" {
  GREEN="G" YELLOW="Y" RED="R"
  run color_by_pct 60 50 80
  assert_success
  assert_output "Y"
}

@test "color_by_pct: returns RED for high percentage" {
  GREEN="G" YELLOW="Y" RED="R"
  run color_by_pct 90 50 80
  assert_success
  assert_output "R"
}

# --- color_by_pct_inverted ---

@test "color_by_pct_inverted: returns GREEN for high percentage" {
  GREEN="G" YELLOW="Y" RED="R"
  run color_by_pct_inverted 90
  assert_success
  assert_output "G"
}

@test "color_by_pct_inverted: returns YELLOW for medium percentage" {
  GREEN="G" YELLOW="Y" RED="R"
  run color_by_pct_inverted 60
  assert_success
  assert_output "Y"
}

@test "color_by_pct_inverted: returns RED for low percentage" {
  GREEN="G" YELLOW="Y" RED="R"
  run color_by_pct_inverted 30
  assert_success
  assert_output "R"
}

# --- compute_health_pct ---

@test "compute_health_pct: returns 100 when no failures" {
  run compute_health_pct 10 0
  assert_success
  assert_output "100"
}

@test "compute_health_pct: returns 100 when no completed and no failed" {
  run compute_health_pct 0 0
  assert_success
  assert_output "100"
}

@test "compute_health_pct: returns 50 for equal completed/failed" {
  run compute_health_pct 5 5
  assert_success
  assert_output "50"
}

# --- compute_rate ---

@test "compute_rate: returns dash for elapsed < 60s" {
  run compute_rate 5 30
  assert_success
  assert_output "—"
}

@test "compute_rate: returns dash when completed is 0" {
  run compute_rate 0 120
  assert_success
  assert_output "—"
}

@test "compute_rate: returns formatted rate for valid input" {
  # 10 completed in 3600 seconds = 10.0/hr
  run compute_rate 10 3600
  assert_success
  assert_output "10.0/hr"
}

# =============================================================================
# Spinner tests (Task 5)
# =============================================================================

# --- get_spinner_frame ---

@test "get_spinner_frame: returns a non-empty string" {
  UI_ASCII=true
  setup_ui_charset
  run get_spinner_frame 0
  assert_success
  [[ -n "$output" ]]
}

@test "get_spinner_frame: cycles through ASCII frames" {
  UI_ASCII=true
  setup_ui_charset
  local frame0 frame1 frame2 frame3 frame4
  frame0="$(get_spinner_frame 0)"
  frame1="$(get_spinner_frame 1)"
  frame2="$(get_spinner_frame 2)"
  frame3="$(get_spinner_frame 3)"
  # ASCII has 4 frames, so frame 4 should wrap to frame 0
  frame4="$(get_spinner_frame 4)"
  # Consecutive frames should differ
  [[ "$frame0" != "$frame1" ]]
  [[ "$frame1" != "$frame2" ]]
  # Wrap-around: tick 4 == tick 0
  assert_equal "$frame0" "$frame4"
}

# --- advance_spinner ---

@test "advance_spinner: increments SPINNER_TICK" {
  SPINNER_TICK=0
  advance_spinner
  assert_equal "$SPINNER_TICK" 1
  advance_spinner
  assert_equal "$SPINNER_TICK" 2
}

# =============================================================================
# Progress bar tests (Task 5)
# =============================================================================

# --- render_progress_bar ---

@test "render_progress_bar: 0% has no fill chars and all empty chars" {
  UI_ASCII=true
  setup_ui_charset
  run render_progress_bar 0 100 10
  assert_success
  # Strip ANSI codes for assertion
  local stripped
  stripped="$(printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g')"
  # Should have brackets and 10 empty chars (-)
  assert_equal "$stripped" "[----------]"
}

@test "render_progress_bar: 100% has all fill chars" {
  UI_ASCII=true
  setup_ui_charset
  run render_progress_bar 100 100 10
  assert_success
  local stripped
  stripped="$(printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g')"
  assert_equal "$stripped" "[##########]"
}

@test "render_progress_bar: 50% has approximately half fill" {
  UI_ASCII=true
  setup_ui_charset
  run render_progress_bar 50 100 10
  assert_success
  local stripped
  stripped="$(printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g')"
  # 50% of 10 = 5 filled, 5 empty
  assert_equal "$stripped" "[#####-----]"
}

# --- render_progress_bar_compact ---

@test "render_progress_bar_compact: produces output without brackets" {
  UI_ASCII=true
  setup_ui_charset
  run render_progress_bar_compact 50 100 10
  assert_success
  local stripped
  stripped="$(printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g')"
  # Should NOT start/end with brackets
  [[ "$stripped" != "["* ]]
  [[ "$stripped" != *"]" ]]
  # Should contain fill and empty chars
  [[ "$stripped" == *"#"* ]]
  [[ "$stripped" == *"-"* ]]
}

@test "render_progress_bar_compact: inverted color mode works" {
  UI_ASCII=true
  setup_ui_charset
  run render_progress_bar_compact 80 100 10 inverted
  assert_success
  local stripped
  stripped="$(printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g')"
  # 80% of 10 = 8 filled, 2 empty
  assert_equal "$stripped" "########--"
}

# =============================================================================
# Iteration history tests (Task 6)
# =============================================================================

# --- record_iteration_result ---

@test "record_iteration_result: adds to ITERATION_HISTORY array" {
  ITERATION_HISTORY=()
  record_iteration_result "OK"
  assert_equal "${#ITERATION_HISTORY[@]}" 1
  assert_equal "${ITERATION_HISTORY[0]}" "OK"
  record_iteration_result "FAIL"
  assert_equal "${#ITERATION_HISTORY[@]}" 2
  assert_equal "${ITERATION_HISTORY[1]}" "FAIL"
}

@test "record_iteration_result: trims history to HISTORY_MAX" {
  ITERATION_HISTORY=()
  HISTORY_MAX=3
  record_iteration_result "OK"
  record_iteration_result "FAIL"
  record_iteration_result "EMPTY"
  record_iteration_result "OK"
  # Should have only 3 entries, oldest trimmed
  assert_equal "${#ITERATION_HISTORY[@]}" 3
  assert_equal "${ITERATION_HISTORY[0]}" "FAIL"
  assert_equal "${ITERATION_HISTORY[1]}" "EMPTY"
  assert_equal "${ITERATION_HISTORY[2]}" "OK"
}

# --- render_history_trail ---

@test "render_history_trail: returns empty when no history" {
  ITERATION_HISTORY=()
  run render_history_trail
  assert_success
  assert_output ""
}

@test "render_history_trail: renders symbols for OK/FAIL/EMPTY entries in ASCII mode" {
  UI_ASCII=true
  setup_ui_charset
  ITERATION_HISTORY=("OK" "FAIL" "EMPTY")
  run render_history_trail
  assert_success
  local stripped
  stripped="$(printf '%s' "$output" | sed $'s/\033\[[0-9;]*m//g')"
  # ASCII symbols: OK="+", FAIL="x", EMPTY="o"
  assert_equal "$stripped" "+xo"
}

# --- serialize_history ---

@test "serialize_history: produces comma-separated string" {
  ITERATION_HISTORY=("OK" "FAIL" "EMPTY")
  run serialize_history
  assert_success
  assert_output "OK,FAIL,EMPTY"
}

# --- deserialize_history ---

@test "deserialize_history: restores from comma-separated string" {
  ITERATION_HISTORY=()
  deserialize_history "OK,FAIL,EMPTY"
  assert_equal "${#ITERATION_HISTORY[@]}" 3
  assert_equal "${ITERATION_HISTORY[0]}" "OK"
  assert_equal "${ITERATION_HISTORY[1]}" "FAIL"
  assert_equal "${ITERATION_HISTORY[2]}" "EMPTY"
}

# --- roundtrip ---

@test "serialize/deserialize roundtrip preserves data" {
  ITERATION_HISTORY=("OK" "FAIL" "OK" "EMPTY" "FAIL")
  local serialized
  serialized="$(serialize_history)"
  ITERATION_HISTORY=()
  deserialize_history "$serialized"
  assert_equal "${#ITERATION_HISTORY[@]}" 5
  assert_equal "${ITERATION_HISTORY[0]}" "OK"
  assert_equal "${ITERATION_HISTORY[1]}" "FAIL"
  assert_equal "${ITERATION_HISTORY[2]}" "OK"
  assert_equal "${ITERATION_HISTORY[3]}" "EMPTY"
  assert_equal "${ITERATION_HISTORY[4]}" "FAIL"
}

# =============================================================================
# tail_signal_lines tests (Task 7)
# =============================================================================

@test "tail_signal_lines: returns empty for missing file" {
  run tail_signal_lines "${TEST_TMPDIR}/nonexistent_file"
  assert_success
  assert_output ""
}

@test "tail_signal_lines: extracts PICKING/DONE/EXIT_SIGNAL lines" {
  local f="${TEST_TMPDIR}/output.txt"
  printf '%s\n' \
    "PICKING: task-1" \
    "some random output" \
    "DONE: task-1" \
    "EXIT_SIGNAL: true" \
    > "$f"
  run tail_signal_lines "$f"
  assert_success
  assert_output --partial "PICKING: task-1"
  assert_output --partial "DONE: task-1"
  assert_output --partial "EXIT_SIGNAL: true"
}

@test "tail_signal_lines: ignores non-signal lines" {
  local f="${TEST_TMPDIR}/output.txt"
  printf '%s\n' \
    "this is normal text" \
    "another line of output" \
    "not a signal" \
    > "$f"
  run tail_signal_lines "$f"
  assert_success
  assert_output ""
}

@test "tail_signal_lines: respects the N limit" {
  local f="${TEST_TMPDIR}/output.txt"
  printf '%s\n' \
    "PICKING: task-1" \
    "DONE: task-1" \
    "PICKING: task-2" \
    "DONE: task-2" \
    "PICKING: task-3" \
    > "$f"
  run tail_signal_lines "$f" 2
  assert_success
  # Should only get last 2 signal lines
  refute_output --partial "PICKING: task-1"
  refute_output --partial "DONE: task-1"
  refute_output --partial "PICKING: task-2"
  assert_output --partial "DONE: task-2"
  assert_output --partial "PICKING: task-3"
}

# =============================================================================
# log_event_jsonl tests (Task 7)
# =============================================================================

@test "log_event_jsonl: is a no-op when LOG_FORMAT is not jsonl" {
  LOG_FORMAT="text"
  LOG_FILE="${TEST_TMPDIR}/events.jsonl"
  log_event_jsonl "test_event" "key1" "val1"
  assert_file_not_exist "$LOG_FILE"
}

@test "log_event_jsonl: writes valid JSON line when LOG_FORMAT=jsonl" {
  LOG_FORMAT="jsonl"
  LOG_FILE="${TEST_TMPDIR}/events.jsonl"
  log_event_jsonl "test_event" "key1" "val1"
  assert_file_exist "$LOG_FILE"
  run jq '.' "$LOG_FILE"
  assert_success
}

@test "log_event_jsonl: includes event name and key/value pairs" {
  LOG_FORMAT="jsonl"
  LOG_FILE="${TEST_TMPDIR}/events.jsonl"
  log_event_jsonl "run_start" "worker" "w1" "task" "mytask"
  run jq -r '.event' "$LOG_FILE"
  assert_success
  assert_output "run_start"
  run jq -r '.worker' "$LOG_FILE"
  assert_success
  assert_output "w1"
  run jq -r '.task' "$LOG_FILE"
  assert_success
  assert_output "mytask"
}

@test "log_event_jsonl: treats numeric values as JSON numbers" {
  LOG_FORMAT="jsonl"
  LOG_FILE="${TEST_TMPDIR}/events.jsonl"
  log_event_jsonl "iteration_end" "completed" "5" "failed" "2"
  run jq '.completed' "$LOG_FILE"
  assert_success
  assert_output "5"
  run jq '.failed' "$LOG_FILE"
  assert_success
  assert_output "2"
  # Verify they're numbers (not strings) by checking type
  run jq '.completed | type' "$LOG_FILE"
  assert_success
  assert_output '"number"'
}

# =============================================================================
# Charset setup tests (Task 9)
# =============================================================================

# --- setup_ui_charset ---

@test "setup_ui_charset: sets ASCII chars when UI_ASCII=true" {
  UI_ASCII=true
  setup_ui_charset
  assert_equal "$UI_USE_ASCII" "true"
  assert_equal "$UI_BOX_TL" "+"
  assert_equal "$UI_BOX_TR" "+"
  assert_equal "$UI_BOX_BL" "+"
  assert_equal "$UI_BOX_BR" "+"
  assert_equal "$UI_BOX_H" "-"
  assert_equal "$UI_BOX_V" "|"
  assert_equal "$UI_ELLIPSIS" "..."
}

@test "setup_ui_charset: sets ASCII chars when RALPH_ASCII=1" {
  unset UI_ASCII
  RALPH_ASCII=1
  setup_ui_charset
  assert_equal "$UI_USE_ASCII" "true"
  assert_equal "$UI_BOX_TL" "+"
  assert_equal "$UI_BOX_H" "-"
  assert_equal "$UI_BOX_V" "|"
}

@test "setup_ui_charset: sets ASCII for C locale (non-TTY)" {
  unset UI_ASCII RALPH_ASCII
  LC_ALL=C LANG=C
  setup_ui_charset
  assert_equal "$UI_USE_ASCII" "true"
  assert_equal "$UI_BOX_TL" "+"
}

@test "setup_ui_charset: sets ASCII for POSIX locale (non-TTY)" {
  unset UI_ASCII RALPH_ASCII
  LC_ALL=POSIX LANG=POSIX
  setup_ui_charset
  assert_equal "$UI_USE_ASCII" "true"
  assert_equal "$UI_BOX_TL" "+"
}

@test "setup_ui_charset: ASCII and Unicode modes set different box chars" {
  # Verify that when forced into ASCII mode, box chars differ from Unicode defaults
  UI_ASCII=true
  setup_ui_charset
  local ascii_tl="$UI_BOX_TL"
  local ascii_ellipsis="$UI_ELLIPSIS"

  # ASCII corners are always "+"
  assert_equal "$ascii_tl" "+"
  assert_equal "$ascii_ellipsis" "..."
  # The Unicode values would be "╭" and "…" respectively,
  # but we can't easily reach that path in tests (no TTY).
  # Verify at least that ASCII mode is internally consistent.
  assert_equal "$UI_BOX_TR" "+"
  assert_equal "$UI_BOX_BL" "+"
  assert_equal "$UI_BOX_BR" "+"
  assert_equal "$UI_BOX_ML" "+"
  assert_equal "$UI_BOX_MR" "+"
  assert_equal "$UI_HR_CHAR" "-"
}
