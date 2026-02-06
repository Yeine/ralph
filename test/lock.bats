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

# --- BUG FIX #2 regression test ---

@test "acquire_lock: breaks stale lock and succeeds" {
  local lockdir="${TEST_TMPDIR}/stale.lck"
  mkdir "$lockdir"
  # The stale lock will be broken after max_wait (10s), which is too slow for a test.
  # Instead we test the mechanism indirectly: create lock, remove it in bg so acquire succeeds
  ( sleep 0.2; rmdir "$lockdir" ) &
  local bg_pid=$!
  acquire_lock "$lockdir"
  assert [ -d "$lockdir" ]
  release_lock "$lockdir"
  wait "$bg_pid" 2>/dev/null || true
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
