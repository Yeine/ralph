#!/usr/bin/env bash
# lock.sh - Portable file locking (mkdir-based, atomic on all POSIX)

# Detect fractional sleep support once
_LOCK_SLEEP_INTERVAL=""
_LOCK_PID_FILENAME="pid"
_LOCK_MAX_WAIT_DEFAULT=10
_LOCK_MAX_RETRIES_DEFAULT=3

_lock_int_or_default() {
  local value="$1" fallback="$2"
  if [[ -n $value && $value =~ ^[0-9]+$ ]]; then
    printf "%s" "$value"
  else
    printf "%s" "$fallback"
  fi
}

_lock_pid_path() {
  printf "%s/%s" "$1" "$_LOCK_PID_FILENAME"
}

_lock_write_pid() {
  local lockdir="$1"
  printf "%s\n" "$$" >"$(_lock_pid_path "$lockdir")" 2>/dev/null
}

_lock_read_pid() {
  local lockdir="$1"
  local pidfile pid
  pidfile="$(_lock_pid_path "$lockdir")"
  [[ -r $pidfile ]] || return 1
  read -r pid <"$pidfile" || return 1
  [[ $pid =~ ^[0-9]+$ ]] || return 1
  printf "%s" "$pid"
}

_lock_is_stale() {
  local lockdir="$1"
  local pid
  pid="$(_lock_read_pid "$lockdir")" || return 1
  if kill -0 "$pid" 2>/dev/null; then
    return 1
  fi
  return 0
}

_lock_cleanup_dir() {
  local lockdir="$1"
  rm -f "$(_lock_pid_path "$lockdir")" 2>/dev/null || true
  rmdir "$lockdir" 2>/dev/null || true
}

_detect_sleep_interval() {
  if [[ -n $_LOCK_SLEEP_INTERVAL ]]; then return; fi
  if sleep 0.05 2>/dev/null; then
    _LOCK_SLEEP_INTERVAL=0.05
  else
    _LOCK_SLEEP_INTERVAL=1
  fi
}

acquire_lock() {
  local lockdir="$1"
  if [[ -z $lockdir ]]; then
    log_err "Lock path is empty"
    return 1
  fi

  local max_wait
  max_wait="$(_lock_int_or_default "${LOCK_MAX_WAIT:-}" "$_LOCK_MAX_WAIT_DEFAULT")"
  local waited=0
  local retries=0
  local max_retries
  max_retries="$(_lock_int_or_default "${LOCK_MAX_RETRIES:-}" "$_LOCK_MAX_RETRIES_DEFAULT")"

  _detect_sleep_interval
  local sleep_interval="$_LOCK_SLEEP_INTERVAL"
  local max_iterations
  if [[ $sleep_interval == "0.05" ]]; then
    max_iterations=$((max_wait * 20)) # 1/0.05
  else
    max_iterations=$max_wait # 1 iteration per second
  fi

  while true; do
    if mkdir "$lockdir" 2>/dev/null; then
      if ! _lock_write_pid "$lockdir"; then
        _lock_cleanup_dir "$lockdir"
        log_err "Failed to write lock metadata: $lockdir"
        return 1
      fi
      return 0
    fi

    if [[ -L $lockdir ]]; then
      log_err "Lock path is a symlink: $lockdir"
      return 1
    fi
    if [[ -e $lockdir && ! -d $lockdir ]]; then
      log_err "Lock path exists but is not a directory: $lockdir"
      return 1
    fi

    sleep "$sleep_interval"
    waited=$((waited + 1))

    if [[ $waited -ge $max_iterations ]]; then
      if [[ -d $lockdir ]]; then
        if _lock_is_stale "$lockdir"; then
          if [[ $retries -ge $max_retries ]]; then
            log_err "Failed to acquire lock after $max_retries retries: $lockdir"
            return 1
          fi
          log_warn "Lock timeout on $lockdir, breaking stale lock"
          _lock_cleanup_dir "$lockdir"
          retries=$((retries + 1))
          # Reset waited counter so we don't immediately re-trigger stale break
          waited=0
          if mkdir "$lockdir" 2>/dev/null; then
            if ! _lock_write_pid "$lockdir"; then
              _lock_cleanup_dir "$lockdir"
              log_err "Failed to write lock metadata: $lockdir"
              return 1
            fi
            return 0
          fi
          # If mkdir failed (race with another process), loop continues with waited=0
        else
          log_err "Lock timeout on $lockdir (owner active or unknown)"
          return 1
        fi
      else
        if [[ $retries -ge $max_retries ]]; then
          log_err "Failed to acquire lock after $max_retries retries: $lockdir"
          return 1
        fi
        retries=$((retries + 1))
        # Reset waited counter so we don't immediately re-trigger timeout
        waited=0
      fi
    fi
  done
}

release_lock() {
  local lockdir="$1"
  if [[ -z $lockdir ]]; then
    log_err "Lock path is empty"
    return 1
  fi
  if [[ -L $lockdir ]]; then
    log_warn "Lock path is a symlink, refusing to remove: $lockdir"
    return 0
  fi
  _lock_cleanup_dir "$lockdir"
}
