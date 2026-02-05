#!/usr/bin/env bash
# attempts.sh - JSON-based attempt tracking for failed tasks

init_attempts_file() {
  if [[ ! -f "${ATTEMPTS_FILE:-}" ]]; then
    echo "{}" > "$ATTEMPTS_FILE"
  fi
}

clear_attempts() {
  echo "{}" > "$ATTEMPTS_FILE"
}

get_attempts() {
  local task="$1"
  local key
  key="$(task_hash "$task")"
  jq -r --arg key "$key" '.[$key].attempts // 0' "$ATTEMPTS_FILE" 2>/dev/null || echo "0"
}

increment_attempts() {
  local task="$1"
  local key
  key="$(task_hash "$task")"
  local current new_count now tmp_file
  local lock_name="${ATTEMPTS_FILE}.lck"

  acquire_lock "$lock_name" || { log_err "Could not acquire lock for attempts"; return 1; }
  current="$(get_attempts "$task")"
  new_count=$((current + 1))
  now="$(date '+%Y-%m-%d %H:%M:%S')"
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/ralph_attempts.XXXXXX")"

  jq --arg key "$key" --arg task "$task" --arg now "$now" --argjson n "$new_count" '
    .[$key] = (.[$key] // {})
    | .[$key].task = $task
    | .[$key].attempts = $n
    | .[$key].skipped = (.[$key].skipped // false)
    | .[$key].updated = $now
  ' "$ATTEMPTS_FILE" > "$tmp_file" && mv "$tmp_file" "$ATTEMPTS_FILE" || rm -f "$tmp_file"
  release_lock "$lock_name"

  echo "$new_count"
}

mark_skipped() {
  local task="$1"
  local key
  key="$(task_hash "$task")"
  local now tmp_file
  local lock_name="${ATTEMPTS_FILE}.lck"

  acquire_lock "$lock_name" || { log_err "Could not acquire lock for attempts"; return 1; }
  now="$(date '+%Y-%m-%d %H:%M:%S')"
  tmp_file="$(mktemp "${TMPDIR:-/tmp}/ralph_attempts.XXXXXX")"

  jq --arg key "$key" --arg task "$task" --arg now "$now" '
    .[$key] = (.[$key] // {})
    | .[$key].task = $task
    | .[$key].skipped = true
    | .[$key].updated = $now
    | .[$key].attempts = (.[$key].attempts // 0)
  ' "$ATTEMPTS_FILE" > "$tmp_file" && mv "$tmp_file" "$ATTEMPTS_FILE" || rm -f "$tmp_file"
  release_lock "$lock_name"
}

get_skipped_tasks() {
  jq -r 'to_entries | .[] | select(.value.skipped == true) | .value.task' "${ATTEMPTS_FILE:-/dev/null}" 2>/dev/null || true
}

show_attempts() {
  log_info "Current attempt tracking state"
  echo ""
  if [[ -s "$ATTEMPTS_FILE" && "$(cat "$ATTEMPTS_FILE")" != "{}" ]]; then
    jq -r '
      to_entries
      | sort_by(.value.skipped, .value.attempts)
      | .[]
      | if .value.skipped == true
        then "\(.value.task): SKIPPED (attempts=\(.value.attempts))"
        else "\(.value.task): \(.value.attempts) attempts"
        end
    ' "$ATTEMPTS_FILE"
  else
    echo "No attempts tracked yet."
  fi
}
