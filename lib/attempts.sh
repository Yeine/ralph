#!/usr/bin/env bash
# attempts.sh - JSON-based attempt tracking for failed tasks

# Helper: acquire lock, ensure file exists, apply jq transform, release lock.
# Usage: _atomic_update_attempts <jq_filter> [jq_args...]
# Pass an empty filter "" to skip the jq step (used by init/clear to just ensure file exists).
_atomic_update_attempts() {
  local jq_filter="$1"; shift
  local lock_name="${ATTEMPTS_FILE}.lck"
  acquire_lock "$lock_name" || { log_err "Could not acquire lock for attempts"; return 1; }
  if [[ ! -f "$ATTEMPTS_FILE" ]]; then
    local init_tmp
    init_tmp="$(mktemp "${TMPDIR:-/tmp}/ralph_attempts.XXXXXX")" || { log_err "Failed to create temp file for attempts"; release_lock "$lock_name"; return 1; }
    printf "%s\n" "{}" > "$init_tmp"
    if ! mv "$init_tmp" "$ATTEMPTS_FILE"; then
      rm -f "$init_tmp"; release_lock "$lock_name"
      log_err "Failed to initialize attempts file: $ATTEMPTS_FILE"; return 1
    fi
  fi
  if [[ -n "$jq_filter" ]]; then
    local tmp_file
    tmp_file="$(mktemp "${TMPDIR:-/tmp}/ralph_attempts.XXXXXX")" || { log_err "Failed to create temp file for attempts"; release_lock "$lock_name"; return 1; }
    if jq "$jq_filter" "$@" "$ATTEMPTS_FILE" > "$tmp_file"; then
      if mv "$tmp_file" "$ATTEMPTS_FILE"; then
        release_lock "$lock_name"; return 0
      fi
    fi
    rm -f "$tmp_file"; release_lock "$lock_name"
    log_err "Failed to update attempts file: $ATTEMPTS_FILE"; return 1
  fi
  release_lock "$lock_name"
}

init_attempts_file() {
  [[ -f "${ATTEMPTS_FILE:-}" ]] && return 0
  _atomic_update_attempts ""
}

clear_attempts() {
  _atomic_update_attempts '{}'
}

get_attempts() {
  local task="$1"
  local key
  key="$(task_hash "$task")"
  jq -r --arg key "$key" '(.[$key].attempts // 0) | if type == "number" then . else 0 end' "$ATTEMPTS_FILE" 2>/dev/null || echo "0"
}

increment_attempts() {
  local task="$1"
  local key
  key="$(task_hash "$task")"
  local current new_count now
  current="$(get_attempts "$task")"
  new_count=$((current + 1))
  now="$(date '+%Y-%m-%d %H:%M:%S')"

  # shellcheck disable=SC2016
  _atomic_update_attempts \
    '.[$key] = (.[$key] // {})
    | .[$key].task = $task
    | .[$key].attempts = $n
    | .[$key].skipped = (.[$key].skipped // false)
    | .[$key].updated = $now' \
    --arg key "$key" --arg task "$task" --arg now "$now" --argjson n "$new_count" \
    || return 1

  echo "$new_count"
}

mark_skipped() {
  local task="$1"
  local key
  key="$(task_hash "$task")"
  local now
  now="$(date '+%Y-%m-%d %H:%M:%S')"

  # shellcheck disable=SC2016
  _atomic_update_attempts \
    '.[$key] = (.[$key] // {})
    | .[$key].task = $task
    | .[$key].skipped = true
    | .[$key].updated = $now
    | .[$key].attempts = ((.[$key].attempts // 0) | if type == "number" then . else 0 end)' \
    --arg key "$key" --arg task "$task" --arg now "$now"
}

get_skipped_tasks() {
  jq -r 'to_entries | .[] | select(.value.skipped == true) | .value.task' "${ATTEMPTS_FILE:-/dev/null}" 2>/dev/null || true
}

show_attempts() {
  log_info "Current attempt tracking state"
  echo ""
  if [[ ! -s "$ATTEMPTS_FILE" ]]; then
    echo "No attempts tracked yet."
    return 0
  fi
  if ! jq -e 'type == "object"' "$ATTEMPTS_FILE" >/dev/null 2>&1; then
    log_err "Failed to parse attempts file: $ATTEMPTS_FILE"
    return 1
  fi
  if jq -e 'length > 0' "$ATTEMPTS_FILE" >/dev/null 2>&1; then
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
