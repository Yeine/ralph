#!/usr/bin/env bats
# Tests for run_with_timeout process-group handling

setup()    { load 'test_helper/common-setup'; _common_setup; }
teardown() { _common_teardown; }

# Helper script that spawns a child (which spawns a grandchild), all sleeping.
# Each writes its PID to a file so the test can verify they're dead.
_make_sleeper_script() {
  local script="$1" pidfile_child="$2" pidfile_grandchild="$3"
  cat > "$script" <<SCRIPT
#!/usr/bin/env bash
# Grandchild
(
  echo \$\$ > "$pidfile_grandchild"
  sleep 300
) &
echo \$\$ > "$pidfile_child"
sleep 300
SCRIPT
  chmod +x "$script"
}

@test "run_with_timeout: returns 124 when command exceeds timeout" {
  run run_with_timeout 1 sleep 30
  assert_failure 124
}

@test "run_with_timeout: kills process group on timeout (no orphans)" {
  local script="${TEST_TMPDIR}/sleeper.sh"
  local pidfile_child="${TEST_TMPDIR}/child.pid"
  local pidfile_grandchild="${TEST_TMPDIR}/grandchild.pid"
  _make_sleeper_script "$script" "$pidfile_child" "$pidfile_grandchild"

  run run_with_timeout 1 "$script"
  assert_failure 124

  # Give processes a moment to be cleaned up
  sleep 1

  # Both child and grandchild should be dead
  if [[ -f "$pidfile_child" ]]; then
    local child_pid
    child_pid="$(cat "$pidfile_child")"
    if kill -0 "$child_pid" 2>/dev/null; then
      kill -9 "$child_pid" 2>/dev/null || true
      fail "Child process $child_pid was still alive after timeout"
    fi
  fi
  if [[ -f "$pidfile_grandchild" ]]; then
    local grandchild_pid
    grandchild_pid="$(cat "$pidfile_grandchild")"
    if kill -0 "$grandchild_pid" 2>/dev/null; then
      kill -9 "$grandchild_pid" 2>/dev/null || true
      fail "Grandchild process $grandchild_pid was still alive after timeout"
    fi
  fi
}

@test "run_with_timeout: preserves exit code on success" {
  run run_with_timeout 5 bash -c 'exit 0'
  assert_success
}

@test "run_with_timeout: preserves exit code on failure" {
  run run_with_timeout 5 bash -c 'exit 42'
  assert_failure 42
}

@test "run_with_timeout: captures stdout from timed command" {
  run run_with_timeout 5 echo "hello from timeout"
  assert_success
  assert_output "hello from timeout"
}
