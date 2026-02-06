#!/usr/bin/env bash
# claims.sh - Worker claims for parallel task coordination

# Global state (set in setup_worker_state)
CLAIMS_FILE="${CLAIMS_FILE:-}"
CLAIMS_LOCK="${CLAIMS_LOCK:-}"

_claims_require_lock() {
  if [[ -z ${CLAIMS_LOCK:-} ]]; then
    log_err "Claims lock path is empty"
    return 1
  fi
  return 0
}

_claims_validate_worker_id() {
  local worker_id="$1"
  if [[ -z $worker_id || ! $worker_id =~ ^[0-9]+$ ]]; then
    log_err "Invalid worker id for claims: $worker_id"
    return 1
  fi
  return 0
}

# Encode task text for claims file storage (avoid delimiter collisions)
encode_claim_task() {
  local task="$1"
  printf '%s' "$task" | base64 | tr -d '\n\r'
}

# Decode task text from claims file storage (fallback to raw if not base64)
decode_claim_task() {
  local encoded="$1" decoded=""
  if decoded="$(printf '%s' "$encoded" | base64 --decode 2>/dev/null)"; then
    printf '%s' "$decoded"
    return 0
  fi
  if decoded="$(printf '%s' "$encoded" | base64 -D 2>/dev/null)"; then
    printf '%s' "$decoded"
    return 0
  fi
  if decoded="$(printf '%s' "$encoded" | base64 -d 2>/dev/null)"; then
    printf '%s' "$decoded"
    return 0
  fi
  printf '%s' "$encoded"
}

# Update this worker's claimed task in the shared claims file
update_claim() {
  local worker_id="$1" task="$2"
  [[ -z ${CLAIMS_FILE:-} ]] && return 0
  _claims_require_lock || return 1
  _claims_validate_worker_id "$worker_id" || return 1
  local now tmp_file
  now="$(date '+%s')"
  local encoded_task
  encoded_task="$(encode_claim_task "$task")"
  acquire_lock "$CLAIMS_LOCK" || {
    log_err "Could not acquire lock for claims: $CLAIMS_LOCK"
    return 1
  }
  tmp_file="$(mktemp "${CLAIMS_FILE}.XXXXXX")" || {
    log_err "Failed to create temp claims file: $CLAIMS_FILE"
    release_lock "$CLAIMS_LOCK"
    return 1
  }
  # Remove existing claim for this worker, then append new one
  if [[ -f $CLAIMS_FILE ]]; then
    if ! awk -F'|' -v wid="W${worker_id}" '$1 != wid' "$CLAIMS_FILE" >"$tmp_file"; then
      rm -f "$tmp_file"
      release_lock "$CLAIMS_LOCK"
      log_err "Failed to update claims file: $CLAIMS_FILE"
      return 1
    fi
  fi
  if ! printf '%s\n' "W${worker_id}|${now}|$$|${encoded_task}" >>"$tmp_file"; then
    rm -f "$tmp_file"
    release_lock "$CLAIMS_LOCK"
    log_err "Failed to write claims file: $CLAIMS_FILE"
    return 1
  fi
  if ! mv "$tmp_file" "$CLAIMS_FILE"; then
    rm -f "$tmp_file"
    release_lock "$CLAIMS_LOCK"
    log_err "Failed to write claims file: $CLAIMS_FILE"
    return 1
  fi
  release_lock "$CLAIMS_LOCK"
}

# Clear this worker's claim (task completed or iteration done)
clear_claim() {
  local worker_id="$1"
  [[ -z ${CLAIMS_FILE:-} ]] && return 0
  _claims_require_lock || return 1
  _claims_validate_worker_id "$worker_id" || return 1
  acquire_lock "$CLAIMS_LOCK" || {
    log_err "Could not acquire lock for claims: $CLAIMS_LOCK"
    return 1
  }
  if [[ -f $CLAIMS_FILE ]]; then
    local tmp_file
    tmp_file="$(mktemp "${CLAIMS_FILE}.XXXXXX")" || {
      log_err "Failed to create temp claims file: $CLAIMS_FILE"
      release_lock "$CLAIMS_LOCK"
      return 1
    }
    if ! awk -F'|' -v wid="W${worker_id}" '$1 != wid' "$CLAIMS_FILE" >"$tmp_file"; then
      rm -f "$tmp_file"
      release_lock "$CLAIMS_LOCK"
      log_err "Failed to update claims file: $CLAIMS_FILE"
      return 1
    fi
    if ! mv "$tmp_file" "$CLAIMS_FILE"; then
      rm -f "$tmp_file"
      release_lock "$CLAIMS_LOCK"
      log_err "Failed to write claims file: $CLAIMS_FILE"
      return 1
    fi
  fi
  release_lock "$CLAIMS_LOCK"
}

# Get tasks currently claimed by OTHER workers (excludes stale claims)
# BUG FIX #3: Read file under lock, process outside lock
get_other_claims() {
  local my_worker_id="$1"
  [[ -z ${CLAIMS_FILE:-} || ! -f ${CLAIMS_FILE:-} ]] && return 0
  _claims_require_lock || return 1
  _claims_validate_worker_id "$my_worker_id" || return 1
  local now stale_threshold file_content
  now="$(date '+%s')"
  stale_threshold=$((ITERATION_TIMEOUT * 2))

  # Read file content under lock (fast), then release
  acquire_lock "$CLAIMS_LOCK" || {
    log_err "Could not acquire lock for claims: $CLAIMS_LOCK"
    return 1
  }
  file_content=""
  [[ -f $CLAIMS_FILE ]] && file_content="$(cat "$CLAIMS_FILE")"
  release_lock "$CLAIMS_LOCK"

  # Process outside the lock
  # Supports both 3-field (WID|ts|b64task) and 4-field (WID|ts|pid|b64task) formats
  [[ -z $file_content ]] && return 0
  while IFS='|' read -r wid ts field3 field4 _rest; do
    [[ -z $wid || -z $ts ]] && continue
    [[ $wid =~ ^W[0-9]+$ ]] || continue
    [[ $ts =~ ^[0-9]+$ ]] || continue
    # Determine format: if field4 is set, field3 is pid; otherwise field3 is encoded_task
    local claim_pid="" encoded_task=""
    if [[ -n $field4 ]]; then
      claim_pid="$field3"
      encoded_task="${field4%$'\r'}"
    else
      encoded_task="${field3%$'\r'}"
    fi
    [[ -z $encoded_task ]] && continue
    # Skip our own claims
    [[ $wid == "W${my_worker_id}" ]] && continue
    # Skip claims from dead processes
    if [[ -n $claim_pid && $claim_pid =~ ^[0-9]+$ ]]; then
      if ! kill -0 "$claim_pid" 2>/dev/null; then
        continue
      fi
    fi
    # Skip stale claims (fallback for old format without pid)
    local age=$((now - ts))
    [[ $age -gt $stale_threshold ]] && continue
    local task
    task="$(decode_claim_task "$encoded_task")"
    [[ -z $task ]] && continue
    task="${task//$'\n'/ }"
    task="${task//$'\r'/ }"
    [[ -z $task ]] && continue
    printf '%s\n' "$task"
  done <<<"$file_content" 2>/dev/null || true
}
