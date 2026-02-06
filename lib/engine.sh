#!/usr/bin/env bash
# shellcheck disable=SC2034  # Variables are used across sourced lib files
# engine.sh - Claude/Codex execution and JSONL parsing

# Count tool_use events from Claude stream-json JSONL output
count_tool_calls_from_jsonl() {
  local jsonl_file="$1"
  awk 'BEGIN{RS="\n"} /^[[:space:]]*\{/{print}' "$jsonl_file" 2>/dev/null \
    | jq -r '
        select(.message.content != null and (.message.content | type) == "array")
        | .message.content[]
        | select(.type == "tool_use")
        | 1
      ' 2>/dev/null \
    | wc -l | tr -d ' ' || echo "0"
}

# Count tool-like events from Codex JSONL stream (--json output)
count_tool_calls_from_codex_jsonl() {
  local jsonl_file="$1"
  local raw_count
  raw_count="$(awk 'BEGIN{RS="\n"} /^[[:space:]]*\{/{print}' "$jsonl_file" 2>/dev/null \
    | jq -r '
        select(
          .type == "item.started" and
          (.item.type == "command_execution" or .item.type == "file_change" or .item.type == "mcp_tool_call")
        ) | 1
      ' 2>/dev/null \
    | wc -l | tr -d ' ' || echo "0")"
  [[ -z "$raw_count" ]] && raw_count=0
  echo "$raw_count"
}

# Run the AI engine (Claude or Codex) in a subshell
# Writes exit codes to pipe_rc_file and jq_rc_file for the caller
run_engine() {
  local prompt_content="$1"
  local engine="$2"
  local raw_jsonl="$3"
  local output_file="$4"
  local pipe_rc_file="$5"
  local jq_rc_file="$6"
  local timeout_seconds="$7"
  local quiet="$8"
  local codex_flags="${9:-}"
  local log_file="${10:-}"

  (
    set +e
    # Ensure pipeline processes are killed when this subshell exits
    _engine_self="$(sh -c 'echo $PPID')"
    trap 'pkill -P "$_engine_self" 2>/dev/null; exit' INT TERM

    # Helper: display + capture a line of output
    _process_line() {
      local line="$1"
      local safe_line
      safe_line="$(sanitize_tty_text "$line")"
      if [[ "$quiet" == "false" ]]; then
        # Clear any in-place status line before printing engine output
        # Skip when stdout is not a TTY (e.g. worker log files) to avoid
        # \r\033[K overwriting the [Wn] prefix added by tail
        is_tty && clear_status_line
        if [[ "$line" == ">>> "* ]]; then
          # Tool-call announcements: compact dim format
          printf "%b\n" "${DIM}${safe_line}${NC}"
        elif [[ "$line" == "PICKING:"* ]]; then
          printf "%b\n" "${BOLD}${ORANGE}${safe_line}${NC}"
        elif [[ "$line" == "DONE:"* || "$line" == "MARKING"* ]]; then
          printf "%b\n" "${BOLD}${GREEN}${safe_line}${NC}"
        elif [[ "$line" == "REMAINING:"* ]]; then
          printf "%b\n" "${DIM}${safe_line}${NC}"
        elif [[ "$line" == "ATTEMPT_FAILED:"* ]]; then
          printf "%b\n" "${BOLD}${RED}${safe_line}${NC}"
        elif [[ "$line" == "EXIT_SIGNAL:"* ]]; then
          printf "%b\n" "${BOLD}${CYAN}${safe_line}${NC}"
        fi
      fi

      if printf '%s\n' "$line" | grep -qiE "^(PICKING|WRITING|TESTING|PASSED|MARKING|DONE|REMAINING|EXIT_SIGNAL|ATTEMPT_FAILED|>>> )"; then
        # Deduplicate: skip signals we've already recorded (e.g. agent emits DONE: twice)
        # Tool calls (">>> ") are exempt — duplicates are expected there.
        if [[ "$line" != ">>> "* ]] && grep -qFx "$line" "$output_file" 2>/dev/null; then
          return
        fi
        printf '%s\n' "$line" >> "$output_file"
        [[ -n "$log_file" ]] && printf '%s\n' "$safe_line" >> "$log_file"
      fi

      # Real-time claim update for parallel coordination
      if [[ "$line" == "PICKING:"* && "${WORKER_ID:-0}" -gt 0 ]]; then
        update_claim "$WORKER_ID" "${line#PICKING: }" 2>/dev/null || true
      fi
    }

    if [[ "$engine" == "codex" ]]; then
      local -a codex_args=()
      if [[ -n "$codex_flags" ]]; then
        # Split on whitespace to avoid eval and command injection.
        read -r -a codex_args <<< "$codex_flags"
      fi
      # Codex path: JSONL output via --json, parsed with jq
      printf '%s' "$prompt_content" \
      | run_with_timeout "$timeout_seconds" \
          codex exec "${codex_args[@]}" --json - \
          2>/dev/null \
      | tee "$raw_jsonl" \
      | jq -r --unbuffered '
          if .type == "item.completed" and .item.type == "agent_message" then
              .item.text // empty
          elif .type == "item.started" and .item.type == "command_execution" then
              ">>> Bash: " + (.item.command // "" | split("\n") | first | .[0:80])
          elif .type == "item.started" and .item.type == "file_change" then
              ">>> Edit: " + (.item.path // .item.file // "" | split("/") | last)
          else
              empty
          end
        ' 2>/dev/null \
      | while IFS= read -r line; do
          _process_line "$line"
        done

      # pipe: printf[0] | run_with_timeout[1] | tee[2] | jq[3] | while[4]
      _pstat=("${PIPESTATUS[@]}")
      echo "${_pstat[1]}" > "$pipe_rc_file"
      echo "${_pstat[3]}" > "$jq_rc_file"
    else
      # Claude path: stream-json output parsed via jq
      local claude_args=(-p "$prompt_content" --verbose --output-format stream-json)
      if [[ -n "${ALLOWED_TOOLS:-}" ]]; then
        claude_args+=(--allowedTools "$ALLOWED_TOOLS")
      fi
      if [[ -n "${DISALLOWED_TOOLS:-}" ]]; then
        claude_args+=(--disallowedTools "$DISALLOWED_TOOLS")
      fi
      run_with_timeout "$timeout_seconds" \
        claude "${claude_args[@]}" \
          </dev/null 2>&1 \
      | tee "$raw_jsonl" \
      | jq -r --unbuffered '
          if .message.content != null and (.message.content | type) == "array" then
              (.message.content[] | select(.type == "text") | .text),
              (.message.content[] | select(.type == "tool_use") |
                  if .name == "Edit" or .name == "Write" or .name == "Read" then
                      ">>> " + .name + ": " + (.input.file_path // "" | split("/") | last)
                  elif .name == "Bash" then
                      ">>> Bash: " + (.input.command // "" | split("\n") | first | .[0:80])
                  else
                      ">>> " + .name
                  end)
          elif .result != null then
              .result
          else
              empty
          end
      ' 2>/dev/null \
      | while IFS= read -r line; do
          _process_line "$line"
        done

      # pipe: run_with_timeout[0] | tee[1] | jq[2] | while[3]
      _pstat=("${PIPESTATUS[@]}")
      echo "${_pstat[0]}" > "$pipe_rc_file"
      echo "${_pstat[2]}" > "$jq_rc_file"
    fi
    exit 0
  ) &
  local engine_pid=$!
  CLAUDE_PID=$engine_pid
  wait "$engine_pid" || true
  CLAUDE_PID=""
}
