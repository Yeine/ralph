#!/usr/bin/env bash
# claims.sh - Worker claims for parallel task coordination

# Global state (set in setup_worker_state)
CLAIMS_FILE="${CLAIMS_FILE:-}"
CLAIMS_LOCK="${CLAIMS_LOCK:-}"

# Encode task text for claims file storage (avoid delimiter collisions)
encode_claim_task() {
  local task="$1"
  printf '%s' "$task" | base64 | tr -d '\n'
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
  [[ -z "${CLAIMS_FILE:-}" ]] && return 0
  local now
  now="$(date '+%s')"
  local encoded_task
  encoded_task="$(encode_claim_task "$task")"
  acquire_lock "$CLAIMS_LOCK"
  # Remove existing claim for this worker, then append new one
  if [[ -f "$CLAIMS_FILE" ]]; then
    grep -v "^W${worker_id}|" "$CLAIMS_FILE" > "${CLAIMS_FILE}.tmp" 2>/dev/null || true
    mv "${CLAIMS_FILE}.tmp" "$CLAIMS_FILE"
  fi
  echo "W${worker_id}|${now}|${encoded_task}" >> "$CLAIMS_FILE"
  release_lock "$CLAIMS_LOCK"
}

# Clear this worker's claim (task completed or iteration done)
clear_claim() {
  local worker_id="$1"
  [[ -z "${CLAIMS_FILE:-}" ]] && return 0
  acquire_lock "$CLAIMS_LOCK"
  if [[ -f "$CLAIMS_FILE" ]]; then
    grep -v "^W${worker_id}|" "$CLAIMS_FILE" > "${CLAIMS_FILE}.tmp" 2>/dev/null || true
    mv "${CLAIMS_FILE}.tmp" "$CLAIMS_FILE"
  fi
  release_lock "$CLAIMS_LOCK"
}

# Get tasks currently claimed by OTHER workers (excludes stale claims)
# BUG FIX #3: Read file under lock, process outside lock
get_other_claims() {
  local my_worker_id="$1"
  [[ -z "${CLAIMS_FILE:-}" || ! -f "${CLAIMS_FILE:-}" ]] && return 0
  local now stale_threshold file_content
  now="$(date '+%s')"
  stale_threshold=$(( ITERATION_TIMEOUT * 2 ))

  # Read file content under lock (fast), then release
  acquire_lock "$CLAIMS_LOCK"
  file_content=""
  [[ -f "$CLAIMS_FILE" ]] && file_content="$(cat "$CLAIMS_FILE")"
  release_lock "$CLAIMS_LOCK"

  # Process outside the lock
  [[ -z "$file_content" ]] && return 0
  while IFS='|' read -r wid ts encoded_task; do
    [[ -z "$wid" || -z "$ts" || -z "$encoded_task" ]] && continue
    # Skip our own claims
    [[ "$wid" == "W${my_worker_id}" ]] && continue
    # Skip stale claims
    local age=$(( now - ts ))
    [[ "$age" -gt "$stale_threshold" ]] && continue
    local task
    task="$(decode_claim_task "$encoded_task")"
    [[ -z "$task" ]] && continue
    echo "$task"
  done <<< "$file_content" 2>/dev/null || true
}
