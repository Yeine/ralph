#!/usr/bin/env bats
# Tests for lib/lock.sh

setup()    { load 'test_helper/common-setup'; _common_setup; }
teardown() { _common_teardown; }

# --- acquire_lock / release_lock ---

@test "acquire_lock: creates lock directory" {
  local lockdir="${TEST_TMPDIR}/test.lck"
  acquire_lock "$lockdir"
  assert [ -d "$lockdir" ]
  release_lock "$lockdir"
}

@test "release_lock: removes lock directory" {
  local lockdir="${TEST_TMPDIR}/test.lck"
  acquire_lock "$lockdir"
  release_lock "$lockdir"
  assert [ ! -d "$lockdir" ]
}

@test "release_lock: is idempotent (no error on missing lock)" {
  local lockdir="${TEST_TMPDIR}/nonexistent.lck"
  run release_lock "$lockdir"
  assert_success
}

@test "acquire_lock: blocks then succeeds when lock released" {
  local lockdir="${TEST_TMPDIR}/blocking.lck"
  mkdir "$lockdir"
  # Release lock in background after 0.3s
  ( sleep 0.3; rmdir "$lockdir" ) &
  local bg_pid=$!
  acquire_lock "$lockdir"
  assert [ -d "$lockdir" ]
  release_lock "$lockdir"
  wait "$bg_pid" 2>/dev/null || true
}

@test "acquire_lock: fails when path is a regular file" {
  local lockpath="${TEST_TMPDIR}/notadir.lck"
  touch "$lockpath"
  run acquire_lock "$lockpath"
  assert_failure
}

@test "acquire_lock: fails when path is a symlink" {
  local lockpath="${TEST_TMPDIR}/symlink.lck"
  ln -s "does-not-exist" "$lockpath" || skip "symlinks unsupported"
  run acquire_lock "$lockpath"
  assert_failure
}

@test "acquire_lock: does not break active lock with live pid" {
  local lockdir="${TEST_TMPDIR}/active.lck"
  mkdir "$lockdir"
  printf "%s\n" "$$" > "$lockdir/pid"
  LOCK_MAX_WAIT=1 LOCK_MAX_RETRIES=1 run acquire_lock "$lockdir"
  assert_failure
  release_lock "$lockdir"
}

@test "acquire_lock: breaks stale lock with dead pid and succeeds" {
  local lockdir="${TEST_TMPDIR}/stale.lck"
  mkdir "$lockdir"
  printf "%s\n" "999999" > "$lockdir/pid"
  LOCK_MAX_WAIT=1 LOCK_MAX_RETRIES=1 run acquire_lock "$lockdir"
  assert_success
  assert [ -d "$lockdir" ]
  assert_file_exists "$lockdir/pid"
  release_lock "$lockdir"
}

@test "acquire_lock: respects max retries for stale lock" {
  local lockdir="${TEST_TMPDIR}/stale-retry.lck"
  mkdir "$lockdir"
  printf "%s\n" "999999" > "$lockdir/pid"
  LOCK_MAX_WAIT=0 LOCK_MAX_RETRIES=0 run acquire_lock "$lockdir"
  assert_failure
  assert [ -d "$lockdir" ]
  release_lock "$lockdir"
}

@test "acquire_lock: multiple sequential acquires work" {
  local lockdir="${TEST_TMPDIR}/seq.lck"
  acquire_lock "$lockdir"
  release_lock "$lockdir"
  acquire_lock "$lockdir"
  release_lock "$lockdir"
  acquire_lock "$lockdir"
  release_lock "$lockdir"
}
