#!/usr/bin/env bats
# Tests for lib/claims.sh

setup() {
  load 'test_helper/common-setup'; _common_setup
  # Set up claims infrastructure
  WORKER_STATE_DIR="${TEST_TMPDIR}/workers"
  mkdir -p "$WORKER_STATE_DIR"
  CLAIMS_FILE="${WORKER_STATE_DIR}/claims"
  CLAIMS_LOCK="${WORKER_STATE_DIR}/claims.lck"
  touch "$CLAIMS_FILE"
}
teardown() { _common_teardown; }

# --- encode/decode ---

@test "encode_claim_task: produces base64 output" {
  local encoded
  encoded="$(encode_claim_task "hello world")"
  assert [ -n "$encoded" ]
  # Base64 shouldn't contain pipes or newlines
  [[ "$encoded" != *"|"* ]]
  [[ "$encoded" != *$'\n'* ]]
}

@test "decode_claim_task: round-trips with encode" {
  local original="Fix the authentication bug (attempt #2)"
  local encoded decoded
  encoded="$(encode_claim_task "$original")"
  decoded="$(decode_claim_task "$encoded")"
  assert_equal "$decoded" "$original"
}

@test "decode_claim_task: handles special characters" {
  local original='task with "quotes" and $dollars and |pipes|'
  local encoded decoded
  encoded="$(encode_claim_task "$original")"
  decoded="$(decode_claim_task "$encoded")"
  assert_equal "$decoded" "$original"
}

@test "decode_claim_task: returns raw when input is not base64" {
  local raw="not:base64!!"
  local decoded
  decoded="$(decode_claim_task "$raw")"
  assert_equal "$decoded" "$raw"
}

# --- update_claim / clear_claim ---

@test "update_claim: writes to claims file" {
  update_claim 1 "fix auth bug"
  assert_file_not_empty "$CLAIMS_FILE"
  run grep "^W1|" "$CLAIMS_FILE"
  assert_success
}

@test "clear_claim: removes worker's claim" {
  update_claim 1 "fix auth bug"
  clear_claim 1
  run grep "^W1|" "$CLAIMS_FILE"
  assert_failure
}

@test "update_claim: replaces existing claim" {
  update_claim 1 "task A"
  update_claim 1 "task B"
  local count
  count="$(grep -c "^W1|" "$CLAIMS_FILE")"
  assert_equal "$count" "1"
}

@test "update_claim: safely stores tasks with pipes and newlines" {
  local task=$'line1|line2\nline3'
  update_claim 1 "$task"
  local count
  count="$(wc -l < "$CLAIMS_FILE" | tr -d ' ')"
  assert_equal "$count" "1"
  local wid ts encoded decoded
  IFS='|' read -r wid ts encoded < "$CLAIMS_FILE"
  assert_equal "$wid" "W1"
  assert [ -n "$encoded" ]
  [[ "$encoded" != *"|"* ]]
  decoded="$(decode_claim_task "$encoded")"
  assert_equal "$decoded" "$task"
}

@test "update_claim: multiple workers coexist" {
  update_claim 1 "task A"
  update_claim 2 "task B"
  run grep -c "^W" "$CLAIMS_FILE"
  assert_output "2"
}

@test "clear_claim: no-op when worker has no claim" {
  run clear_claim 1
  assert_success
  assert_file_empty "$CLAIMS_FILE"
}

# --- get_other_claims ---

@test "get_other_claims: excludes own claims" {
  update_claim 1 "task A"
  update_claim 2 "task B"
  run get_other_claims 1
  assert_output --partial "task B"
  refute_output --partial "task A"
}

@test "get_other_claims: returns empty when no others" {
  update_claim 1 "task A"
  run get_other_claims 1
  assert_output ""
}

@test "get_other_claims: normalizes newlines to spaces" {
  local task=$'line1\nline2'
  update_claim 2 "$task"
  run get_other_claims 1
  assert_output "line1 line2"
}

@test "get_other_claims: ignores malformed lines" {
  local now encoded
  now="$(date +%s)"
  encoded="$(encode_claim_task "valid task")"
  cat > "$CLAIMS_FILE" <<EOF
bogus line
W2|not_ts|${encoded}
W3|${now}|
W4|${now}|${encoded}
EOF
  run get_other_claims 1
  assert_output "valid task"
}

@test "get_other_claims: skips stale entries" {
  # Write a claim with a very old timestamp
  local stale_ts=$(( $(date +%s) - ITERATION_TIMEOUT * 3 ))
  local encoded
  encoded="$(encode_claim_task "stale task")"
  echo "W5|${stale_ts}|${encoded}" > "$CLAIMS_FILE"
  run get_other_claims 1
  assert_output ""
}

# --- BUG FIX #3 regression test ---

@test "get_other_claims: releases lock promptly" {
  update_claim 2 "task X"
  get_other_claims 1 >/dev/null
  # Lock should be free - we can acquire it immediately
  acquire_lock "$CLAIMS_LOCK"
  assert [ -d "$CLAIMS_LOCK" ]
  release_lock "$CLAIMS_LOCK"
}
