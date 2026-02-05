#!/usr/bin/env bash
# lock.sh - Portable file locking (mkdir-based, atomic on all POSIX)

# Detect fractional sleep support once
_LOCK_SLEEP_INTERVAL=""
_detect_sleep_interval() {
  if [[ -n "$_LOCK_SLEEP_INTERVAL" ]]; then return; fi
  if sleep 0.05 2>/dev/null; then
    _LOCK_SLEEP_INTERVAL=0.05
  else
    _LOCK_SLEEP_INTERVAL=1
  fi
}

acquire_lock() {
  local lockdir="$1"
  local max_wait=10  # seconds
  local waited=0
  local retries=0
  local max_retries=3

  _detect_sleep_interval
  local sleep_interval="$_LOCK_SLEEP_INTERVAL"
  local max_iterations
  if [[ "$sleep_interval" == "0.05" ]]; then
    max_iterations=$((max_wait * 20))  # 1/0.05
  else
    max_iterations=$max_wait  # 1 iteration per second
  fi

  while true; do
    if mkdir "$lockdir" 2>/dev/null; then
      return 0
    fi

    if [[ -e "$lockdir" && ! -d "$lockdir" ]]; then
      log_err "Lock path exists but is not a directory: $lockdir"
      return 1
    fi
    # If the directory vanished between mkdir and this check, just retry
    if [[ ! -e "$lockdir" ]]; then
      continue
    fi

    sleep "$sleep_interval"
    waited=$((waited + 1))

    if [[ "$waited" -ge "$max_iterations" ]]; then
      log_warn "Lock timeout on $lockdir, breaking stale lock"
      rmdir "$lockdir" 2>/dev/null || true
      retries=$((retries + 1))
      if [[ "$retries" -ge "$max_retries" ]]; then
        log_err "Failed to acquire lock after $max_retries retries: $lockdir"
        return 1
      fi
      # BUG FIX #2: Reset waited counter so we don't immediately re-trigger stale break
      waited=0
      if mkdir "$lockdir" 2>/dev/null; then
        return 0
      fi
      # If mkdir failed (race with another process), loop continues with waited=0
    fi
  done
}

release_lock() {
  rmdir "$1" 2>/dev/null || true
}
