#!/usr/bin/env bats
# Tests for lib/utils.sh

setup()    { load 'test_helper/common-setup'; _common_setup; }
teardown() { _common_teardown; }

# --- fmt_hms ---

@test "fmt_hms: formats seconds only" {
  run fmt_hms 45
  assert_output "45s"
}

@test "fmt_hms: formats zero seconds" {
  run fmt_hms 0
  assert_output "0s"
}

@test "fmt_hms: formats minutes and seconds" {
  run fmt_hms 125
  assert_output "2m05s"
}

@test "fmt_hms: formats exactly 60 seconds as 1m" {
  run fmt_hms 60
  assert_output "1m00s"
}

@test "fmt_hms: formats hours" {
  run fmt_hms 3665
  assert_output "1h01m05s"
}

@test "fmt_hms: formats exactly 1 hour" {
  run fmt_hms 3600
  assert_output "1h00m00s"
}

# --- task_hash ---

@test "task_hash: produces consistent output for same input" {
  local h1 h2
  h1="$(task_hash "some task")"
  h2="$(task_hash "some task")"
  assert_equal "$h1" "$h2"
}

@test "task_hash: produces different output for different inputs" {
  local h1 h2
  h1="$(task_hash "task A")"
  h2="$(task_hash "task B")"
  assert [ "$h1" != "$h2" ]
}

@test "task_hash: handles empty string" {
  run task_hash ""
  assert_success
  assert [ -n "$output" ]
}

@test "task_hash: handles special characters" {
  run task_hash "task with 'quotes' and \"double quotes\" and \$dollars"
  assert_success
  assert [ -n "$output" ]
}

# --- pad_right ---

@test "pad_right: pads short string" {
  run pad_right "hi" 10
  assert_output "hi        "
}

@test "pad_right: doesn't truncate long string" {
  run pad_right "hello world" 5
  assert_output "hello world"
}

# --- run_with_timeout ---

@test "run_with_timeout: passes through success" {
  run run_with_timeout 5 true
  assert_success
}

@test "run_with_timeout: passes through failure" {
  run run_with_timeout 5 false
  assert_failure
}

@test "run_with_timeout: returns 124 on timeout" {
  run run_with_timeout 1 sleep 10
  assert_failure 124
}

@test "run_with_timeout: captures command output" {
  run run_with_timeout 5 echo "hello"
  assert_success
  assert_output "hello"
}

# --- pick_ralph_quote ---

@test "pick_ralph_quote: returns non-empty string" {
  local quote
  quote="$(pick_ralph_quote)"
  assert [ -n "$quote" ]
}

# --- generate_run_id ---

@test "generate_run_id: returns non-empty string" {
  local id
  id="$(generate_run_id)"
  assert [ -n "$id" ]
}

@test "generate_run_id: contains a dash separator" {
  local id
  id="$(generate_run_id)"
  [[ "$id" == *-* ]]
}

# --- truncate_ellipsis ---

@test "truncate_ellipsis: returns empty for empty input" {
  run truncate_ellipsis "" 10
  assert_output ""
}

@test "truncate_ellipsis: returns empty for max=0" {
  run truncate_ellipsis "hello" 0
  assert_output ""
}

@test "truncate_ellipsis: passes through short string" {
  run truncate_ellipsis "hi" 10
  assert_output "hi"
}

@test "truncate_ellipsis: truncates long string" {
  local result
  result="$(truncate_ellipsis "hello world" 6)"
  assert_equal "${#result}" 6
}

@test "truncate_ellipsis: ANSI-aware — short colored string passes through" {
  # With NO_COLOR the vars are empty, so use raw escapes
  local colored=$'\033[0;31mhi\033[0m'
  run truncate_ellipsis "$colored" 10
  assert_output "$colored"
}

@test "truncate_ellipsis: ANSI-aware — truncates by visual width" {
  local colored=$'\033[0;31mhello world\033[0m'
  local result
  result="$(truncate_ellipsis "$colored" 6)"
  # Should strip ANSI and truncate to 5 chars + ellipsis = 6 visual chars
  assert_equal "${#result}" 6
}

# --- strip_ansi ---

@test "strip_ansi: strips color codes" {
  local colored=$'\033[0;31mhello\033[0m'
  run strip_ansi "$colored"
  assert_output "hello"
}

@test "strip_ansi: passes plain text through" {
  run strip_ansi "plain text"
  assert_output "plain text"
}

@test "strip_ansi: handles empty string" {
  run strip_ansi ""
  assert_output ""
}

@test "strip_ansi: strips bold + color + dim" {
  local s=$'\033[1m\033[36mtest\033[0m\033[2m dim\033[0m'
  run strip_ansi "$s"
  assert_output "test dim"
}

# --- visual_length ---

@test "visual_length: plain text" {
  run visual_length "hello"
  assert_output "5"
}

@test "visual_length: empty string" {
  run visual_length ""
  assert_output "0"
}

@test "visual_length: ignores ANSI codes" {
  local colored=$'\033[0;31mhello\033[0m'
  run visual_length "$colored"
  assert_output "5"
}

@test "visual_length: complex ANSI" {
  # Visual: "#1 | task | OK" = 14 chars
  local s=$'\033[1m\033[36m#1\033[0m | \033[1;37mtask\033[0m | \033[0;32mOK\033[0m'
  run visual_length "$s"
  assert_output "14"
}
