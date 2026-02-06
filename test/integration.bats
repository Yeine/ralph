#!/usr/bin/env bats
# Integration tests - end-to-end smoke tests for the ralph CLI

setup() {
  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  RALPH_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  TEST_TMPDIR="$(mktemp -d)"
  export NO_COLOR=1
  export ATTEMPTS_FILE="${TEST_TMPDIR}/.ralph_attempts.json"
}
teardown() {
  [[ -d "${TEST_TMPDIR:-}" ]] && rm -rf "$TEST_TMPDIR"
}

make_stub_claude() {
  local bin_dir="$1"
  cat > "${bin_dir}/claude" <<'EOF'
#!/usr/bin/env bash
record_file="${CLAUDE_RECORD:-}"
if [[ -n "$record_file" ]]; then
  {
    for arg in "$@"; do
      printf 'ARG:%s\n' "$arg"
    done
  } > "$record_file"
fi
cat <<'JSON'
{"result":"EXIT_SIGNAL: true"}
JSON
EOF
  chmod +x "${bin_dir}/claude"
}

make_stub_codex() {
  local bin_dir="$1"
  cat > "${bin_dir}/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
record_file="${CODEX_RECORD:-}"
if [[ -n "$record_file" ]]; then
  {
    for arg in "$@"; do
      printf 'ARG:%s\n' "$arg"
    done
  } > "$record_file"
fi
cat >/dev/null
cat <<'JSON'
{"type":"item.completed","item":{"type":"agent_message","text":"EXIT_SIGNAL: true"}}
JSON
EOF
  chmod +x "${bin_dir}/codex"
}

make_stub_caffeinate() {
  local bin_dir="$1"
  cat > "${bin_dir}/caffeinate" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
record_file="${CAFFEINATE_RECORD:-}"
if [[ -n "$record_file" ]]; then
  {
    printf 'RALPH_CAFFEINATED=%s\n' "${RALPH_CAFFEINATED:-}"
    for arg in "$@"; do
      printf 'ARG:%s\n' "$arg"
    done
  } > "$record_file"
fi
exit 0
EOF
  chmod +x "${bin_dir}/caffeinate"
}

# --- --help ---

@test "ralph --help: exits 0 and shows usage" {
  run "${RALPH_ROOT}/bin/ralph" --help
  assert_success
  assert_output --partial "Ralph Loop"
  assert_output --partial "--prompt"
  assert_output --partial "--engine"
  assert_output --partial "--workers"
}

# --- --show-attempts ---

@test "ralph --show-attempts: works with no prior state" {
  run "${RALPH_ROOT}/bin/ralph" --show-attempts
  assert_success
  assert_output --partial "No attempts tracked"
}

# --- --clear-attempts ---

@test "ralph --clear-attempts: resets file" {
  # ralph uses .ralph_attempts.json in CWD by default, so run from tmpdir
  echo '{"k":{"task":"old task","attempts":3,"skipped":false}}' > "${TEST_TMPDIR}/.ralph_attempts.json"
  run bash -c "cd '${TEST_TMPDIR}' && '${RALPH_ROOT}/bin/ralph' --clear-attempts"
  assert_success
  assert_output --partial "Cleared"
  run cat "${TEST_TMPDIR}/.ralph_attempts.json"
  assert_output "{}"
}

# --- missing prompt file ---

@test "ralph: exits with error when prompt file missing" {
  command -v claude >/dev/null 2>&1 || skip "claude not installed"
  run "${RALPH_ROOT}/bin/ralph" --prompt "${TEST_TMPDIR}/nonexistent-file.md"
  assert_failure
  assert_output --partial "not found"
}

# --- invalid engine ---

@test "ralph: exits with error for unknown engine" {
  run "${RALPH_ROOT}/bin/ralph" --engine "gpt4"
  assert_failure
  assert_output --partial "Unknown engine"
}

# --- invalid workers ---

@test "ralph: exits with error for invalid workers count" {
  run "${RALPH_ROOT}/bin/ralph" --workers 0
  assert_failure
  assert_output --partial "Workers must be 1-16"
}

@test "ralph: exits with error for workers > 16" {
  run "${RALPH_ROOT}/bin/ralph" --workers 20
  assert_failure
  assert_output --partial "Workers must be 1-16"
}

# --- unknown option ---

@test "ralph: exits with error for unknown option" {
  run "${RALPH_ROOT}/bin/ralph" --foobar
  assert_failure
  assert_output --partial "Unknown option"
}

# --- --log ---

@test "ralph --log: writes output to log file" {
  local bin_dir="${TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  make_stub_claude "$bin_dir"

  local prompt_file="${TEST_TMPDIR}/prompt.md"
  printf "Test task\n" > "$prompt_file"

  local log_file="${TEST_TMPDIR}/ralph.log"
  run env PATH="${bin_dir}:$PATH" \
    "${RALPH_ROOT}/bin/ralph" \
    --prompt "$prompt_file" \
    --engine "claude" \
    --max 1 \
    --wait 0 \
    --ui minimal \
    --log "$log_file"
  assert_success

  run cat "$log_file"
  assert_success
  assert_output --partial "EXIT_SIGNAL: true"
}

# --- --engine codex ---

@test "ralph --engine codex: runs codex path and emits output" {
  local bin_dir="${TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  make_stub_codex "$bin_dir"

  local record_file="${TEST_TMPDIR}/codex_record"
  local prompt_file="${TEST_TMPDIR}/prompt.md"
  printf "Test task\n" > "$prompt_file"

  run env PATH="${bin_dir}:$PATH" CODEX_RECORD="$record_file" \
    "${RALPH_ROOT}/bin/ralph" \
    --prompt "$prompt_file" \
    --engine "codex" \
    --max 1 \
    --wait 0 \
    --ui minimal
  assert_success
  assert_output --partial "EXIT_SIGNAL detected"
  run cat "$record_file"
  assert_success
  assert_output --partial "ARG:exec"
}

# --- parallel workers ---

@test "ralph --workers: writes per-worker logs in parallel mode" {
  local bin_dir="${TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  make_stub_claude "$bin_dir"

  local prompt_file="${TEST_TMPDIR}/prompt.md"
  printf "Test task\n" > "$prompt_file"

  local base_log="${TEST_TMPDIR}/parallel.log"
  run env PATH="${bin_dir}:$PATH" \
    "${RALPH_ROOT}/bin/ralph" \
    --prompt "$prompt_file" \
    --engine "claude" \
    --max 1 \
    --wait 0 \
    --ui minimal \
    --workers 2 \
    --log "$base_log"
  assert_success

  run cat "${TEST_TMPDIR}/parallel_w1.log"
  assert_success
  assert_output --partial "EXIT_SIGNAL: true"

  # Worker 2 may not run an iteration if worker 1's EXIT_SIGNAL fires first,
  # but its log file should still be created.
  [ -f "${TEST_TMPDIR}/parallel_w2.log" ]
}

# --- --caffeinate ---

@test "ralph --caffeinate: re-execs via caffeinate without leaking flag" {
  local bin_dir="${TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  make_stub_caffeinate "$bin_dir"

  local record_file="${TEST_TMPDIR}/caffeinate_record"
  local prompt_file="${TEST_TMPDIR}/prompt.md"
  printf "Test task\n" > "$prompt_file"

  run env PATH="${bin_dir}:$PATH" CAFFEINATE_RECORD="$record_file" \
    "${RALPH_ROOT}/bin/ralph" \
    --caffeinate \
    --prompt "$prompt_file" \
    --max 1 \
    --wait 0 \
    --ui minimal
  assert_success

  run cat "$record_file"
  assert_success
  assert_output --partial "RALPH_CAFFEINATED=1"
  assert_output --partial "ARG:-i"
  assert_output --partial "/bin/ralph"
  assert_output --partial "ARG:--prompt"
  assert_output --partial "ARG:${prompt_file}"
  refute_output --partial "ARG:--caffeinate"
  refute_output --partial "ARG:-c"
}

# --- --allowed-tools forwarding ---

@test "ralph --allowed-tools: forwards comma-separated tools as separate args" {
  local bin_dir="${TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  make_stub_claude "$bin_dir"

  local record_file="${TEST_TMPDIR}/claude_record"
  local prompt_file="${TEST_TMPDIR}/prompt.md"
  printf "Test task\n" > "$prompt_file"

  run env PATH="${bin_dir}:$PATH" CLAUDE_RECORD="$record_file" \
    "${RALPH_ROOT}/bin/ralph" \
    --prompt "$prompt_file" \
    --engine "claude" \
    --allowed-tools "Read, Bash(git log *),Edit" \
    --max 1 \
    --wait 0 \
    --ui minimal
  assert_success

  run cat "$record_file"
  assert_success
  # Each tool should appear as its own ARG after --allowedTools
  assert_output --partial "ARG:--allowedTools"
  assert_output --partial "ARG:Read"
  assert_output --partial "ARG:Bash(git log *)"
  assert_output --partial "ARG:Edit"
  # Should NOT contain the full comma-separated string as a single arg
  refute_output --partial "ARG:Read, Bash(git log *),Edit"
}

@test "ralph --disallowed-tools: forwards comma-separated tools as separate args" {
  local bin_dir="${TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  make_stub_claude "$bin_dir"

  local record_file="${TEST_TMPDIR}/claude_record"
  local prompt_file="${TEST_TMPDIR}/prompt.md"
  printf "Test task\n" > "$prompt_file"

  run env PATH="${bin_dir}:$PATH" CLAUDE_RECORD="$record_file" \
    "${RALPH_ROOT}/bin/ralph" \
    --prompt "$prompt_file" \
    --engine "claude" \
    --disallowed-tools "Bash, Write" \
    --max 1 \
    --wait 0 \
    --ui minimal
  assert_success

  run cat "$record_file"
  assert_success
  assert_output --partial "ARG:--disallowedTools"
  assert_output --partial "ARG:Bash"
  assert_output --partial "ARG:Write"
  refute_output --partial "ARG:Bash, Write"
}

# --- --codex-flag (repeatable) ---

@test "ralph --codex-flag: forwards repeated flags as separate args to codex" {
  local bin_dir="${TEST_TMPDIR}/bin"
  mkdir -p "$bin_dir"
  make_stub_codex "$bin_dir"

  local record_file="${TEST_TMPDIR}/codex_record"
  local prompt_file="${TEST_TMPDIR}/prompt.md"
  printf "Test task\n" > "$prompt_file"

  run env PATH="${bin_dir}:$PATH" CODEX_RECORD="$record_file" \
    "${RALPH_ROOT}/bin/ralph" \
    --prompt "$prompt_file" \
    --engine "codex" \
    --codex-flag "--full-auto" \
    --codex-flag "--dangerously-auto-approve-everything" \
    --max 1 \
    --wait 0 \
    --ui minimal
  assert_success

  run cat "$record_file"
  assert_success
  assert_output --partial "ARG:exec"
  assert_output --partial "ARG:--full-auto"
  assert_output --partial "ARG:--dangerously-auto-approve-everything"
  assert_output --partial "ARG:--json"
}
