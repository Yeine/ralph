#!/usr/bin/env bats
# Tests for lib/engine.sh JSONL parsing functions

setup()    { load 'test_helper/common-setup'; _common_setup; }
teardown() { _common_teardown; }

# --- count_tool_calls_from_jsonl (Claude stream-json) ---

@test "count_tool_calls_from_jsonl: returns 0 for empty file" {
  local f="${TEST_TMPDIR}/empty.jsonl"
  : > "$f"
  run count_tool_calls_from_jsonl "$f"
  assert_success
  assert_output "0"
}

@test "count_tool_calls_from_jsonl: returns 0 for file with no tool_use entries" {
  local f="${TEST_TMPDIR}/no_tools.jsonl"
  cat > "$f" <<'EOF'
{"message":{"content":[{"type":"text","text":"hello world"}]}}
{"message":{"content":[{"type":"text","text":"goodbye"}]}}
EOF
  run count_tool_calls_from_jsonl "$f"
  assert_success
  assert_output "0"
}

@test "count_tool_calls_from_jsonl: counts tool_use entries correctly" {
  local f="${TEST_TMPDIR}/tools.jsonl"
  cat > "$f" <<'EOF'
{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
{"message":{"content":[{"type":"text","text":"hello"}]}}
{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"foo"}}]}}
EOF
  run count_tool_calls_from_jsonl "$f"
  assert_success
  assert_output "2"
}

@test "count_tool_calls_from_jsonl: handles malformed JSON lines gracefully" {
  local f="${TEST_TMPDIR}/malformed.jsonl"
  cat > "$f" <<'EOF'
{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}
this is not valid json at all
{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"foo"}}]}}
EOF
  run count_tool_calls_from_jsonl "$f"
  assert_success
  assert_output "2"
}

# --- count_tool_calls_from_codex_jsonl (Codex --json) ---

@test "count_tool_calls_from_codex_jsonl: returns 0 for empty file" {
  local f="${TEST_TMPDIR}/empty_codex.jsonl"
  : > "$f"
  run count_tool_calls_from_codex_jsonl "$f"
  assert_success
  assert_output "0"
}

@test "count_tool_calls_from_codex_jsonl: counts command_execution events" {
  local f="${TEST_TMPDIR}/codex_cmd.jsonl"
  cat > "$f" <<'EOF'
{"type":"item.started","item":{"type":"command_execution","command":"ls"}}
{"type":"item.started","item":{"type":"command_execution","command":"pwd"}}
EOF
  run count_tool_calls_from_codex_jsonl "$f"
  assert_success
  assert_output "2"
}

@test "count_tool_calls_from_codex_jsonl: counts file_change events" {
  local f="${TEST_TMPDIR}/codex_file.jsonl"
  cat > "$f" <<'EOF'
{"type":"item.started","item":{"type":"file_change","path":"foo.txt"}}
EOF
  run count_tool_calls_from_codex_jsonl "$f"
  assert_success
  assert_output "1"
}

@test "count_tool_calls_from_codex_jsonl: counts mcp_tool_call events" {
  local f="${TEST_TMPDIR}/codex_mcp.jsonl"
  cat > "$f" <<'EOF'
{"type":"item.started","item":{"type":"mcp_tool_call","name":"fetch"}}
EOF
  run count_tool_calls_from_codex_jsonl "$f"
  assert_success
  assert_output "1"
}

@test "count_tool_calls_from_codex_jsonl: ignores non-matching event types" {
  local f="${TEST_TMPDIR}/codex_mixed.jsonl"
  cat > "$f" <<'EOF'
{"type":"item.started","item":{"type":"command_execution","command":"ls"}}
{"type":"item.started","item":{"type":"agent_message","text":"hi"}}
{"type":"item.started","item":{"type":"file_change","path":"foo.txt"}}
{"type":"item.completed","item":{"type":"command_execution","command":"ls"}}
{"type":"item.started","item":{"type":"mcp_tool_call","name":"fetch"}}
{"type":"response.summary","text":"done"}
EOF
  run count_tool_calls_from_codex_jsonl "$f"
  assert_success
  assert_output "3"
}
