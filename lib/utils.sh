#!/usr/bin/env bash
# utils.sh - Misc utility functions

is_tty() { [[ -t 1 ]]; }

# Format seconds as human-readable duration
fmt_hms() {
  local s="$1"
  local h=$((s / 3600))
  local m=$(((s % 3600) / 60))
  local sec=$((s % 60))
  if [[ $h -gt 0 ]]; then
    printf "%dh%02dm%02ds" "$h" "$m" "$sec"
  elif [[ $m -gt 0 ]]; then
    printf "%dm%02ds" "$m" "$sec"
  else
    printf "%ds" "$sec"
  fi
}

pad_right() {
  local s="$1" width="$2"
  printf "%-*s" "$width" "$s"
}

# Bell sound (alerts user if terminal is backgrounded)
# Usage: bell completion  OR  bell end
bell() {
  local event="${1:-}"
  is_tty || return 0
  case "$event" in
    completion) [[ ${BELL_ON_COMPLETION:-false} == "true" ]] && printf "\a" ;;
    end) [[ ${BELL_ON_END:-false} == "true" ]] && printf "\a" ;;
    *) ;; # ignore unknown
  esac
}

# Run a command with a timeout, portable across macOS/Linux.
# Uses gtimeout/timeout if available, otherwise perl fork+exec.
# Returns 124 on timeout (matching GNU timeout behavior).
run_with_timeout() {
  local seconds="$1"
  shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${seconds}" "$@"
    return $?
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${seconds}" "$@"
    return $?
  else
    # Perl fork+exec+waitpid with proper signal handling.
    # Child runs in its own process group so we can kill the entire group
    # on timeout (catches grandchildren that would otherwise survive).
    perl -e '
      use POSIX qw(:sys_wait_h setpgid);
      my $timeout = shift @ARGV;
      my $pid = fork();
      if (!defined $pid) { die "fork failed: $!" }
      if ($pid == 0) {
        setpgid(0, 0);   # new process group
        exec @ARGV;
        die "exec failed: $!";
      }
      # Ensure child has its own pgid before we might need to kill it
      eval { setpgid($pid, $pid) };

      my $kill_group = sub {
        my ($sig) = @_;
        kill $sig, -$pid;           # signal entire process group
        select(undef, undef, undef, 0.5);  # 0.5s grace
        kill "KILL", -$pid;         # force-kill survivors
        waitpid($pid, WNOHANG);
      };

      eval {
        local $SIG{ALRM} = sub { $kill_group->("TERM"); die "timeout\n" };
        local $SIG{INT}  = sub { $kill_group->("INT");  exit 130; };
        local $SIG{TERM} = sub { $kill_group->("TERM"); exit 143; };
        alarm $timeout;
        waitpid($pid, 0);
        alarm 0;
      };
      if ($@ && $@ eq "timeout\n") {
        exit 124;
      }
      exit ($? >> 8);
    ' -- "$seconds" "$@"
    return $?
  fi
}

# Stable hash for task keys (avoid normalization collisions)
task_hash() {
  local s="$1"
  if command -v shasum >/dev/null 2>&1; then
    printf "%s" "$s" | shasum -a 256 | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    printf "%s" "$s" | openssl dgst -sha256 | awk '{print $2}'
  elif command -v cksum >/dev/null 2>&1; then
    printf "%s" "$s" | cksum | awk '{print "cksum_"$1"_"$2}'
  else
    log_err "No hash command found (need shasum, openssl, or cksum)"
    return 1
  fi
}

# Git state hash to detect file changes (portable macOS/Linux)
# Returns empty string on failure (safe for set -e)
get_file_state_hash() {
  command -v git >/dev/null 2>&1 || {
    echo ""
    return 0
  }
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo ""
    return 0
  }
  case "$PWD/" in
    "$repo_root"/*) ;;
    *)
      echo ""
      return 0
      ;;
  esac
  if command -v md5sum >/dev/null 2>&1; then
    git status --porcelain 2>/dev/null | md5sum 2>/dev/null | cut -c1-8 || echo ""
  elif command -v md5 >/dev/null 2>&1; then
    if md5 -q </dev/null >/dev/null 2>&1; then
      git status --porcelain 2>/dev/null | md5 -q 2>/dev/null | cut -c1-8 || echo ""
    else
      git status --porcelain 2>/dev/null | md5 2>/dev/null | awk '{print $NF}' | cut -c1-8 || echo ""
    fi
  else
    echo ""
  fi
}

# Dependency checks
check_dependencies() {
  local missing=()
  for cmd in jq "${ENGINE:-claude}"; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    log_err "Missing required dependencies: ${missing[*]}"
    log_dim "Install them and try again."
    exit 1
  fi
}

# Show resource usage (best-effort)
show_resources() {
  [[ ${SHOW_RESOURCES:-true} == "true" ]] || return 0
  command -v docker >/dev/null 2>&1 || return 0

  local pattern="${RALPH_DOCKER_PATTERN:-}"
  [[ -z $pattern ]] && return 0

  local docker_stats
  docker_stats="$(docker stats --no-stream --format "{{.Name}}: CPU={{.CPUPerc}} MEM={{.MemUsage}}" 2>/dev/null \
    | grep -E -- "$pattern" | head -3 || true)"
  if [[ -n $docker_stats ]]; then
    log_info "Resources"
    while IFS= read -r line; do
      printf "  %s\n" "$line"
    done <<<"$docker_stats"
  fi
}

# Ralph quotes
RALPH_QUOTES=(
  "I'm helping!"
  "My brain is working!"
  "It tastes like burning!"
  "Haha, I'm in danger!"
  "The crayons are talking to me!"
  "I'm a brick."
  "Slow down, I'm scared!"
  "The world is scary."
  "Go banana!"
  "My cat's breath smells like cat food."
  "This is my sandbox. I'm not allowed to go in the deep end."
  "Me fail English? That's unpossible."
  "Hi, Super Nintendo Chalmers!"
  "I'm learnding!"
  "I bent my Wookiee."
  "I found a moon rock in my nose!"
  "When I grow up, I want to be a principal or a caterpillar."
  "The leprechaun tells me to burn things."
  "I eated the purple berries."
  "My knob tastes funny."
  "Even my boogers are spicy!"
  "I dress myself!"
  "What's a battle?"
  "That's my swingset. I'm not allowed on it."
)

pick_ralph_quote() {
  printf "%s" "${RALPH_QUOTES[RANDOM % ${#RALPH_QUOTES[@]}]}"
}

generate_run_id() {
  local t epoch suffix
  t="$(date '+%H%M%S')"
  epoch="$(date '+%s')"
  if command -v shasum >/dev/null 2>&1; then
    suffix="$(printf "%s" "$epoch" | shasum -a 256 | cut -c1-4)"
  else
    suffix="$((epoch % 10000))"
  fi
  printf "%s-%s" "$t" "$suffix"
}

# CLI usage
usage() {
  cat <<EOF
Ralph Loop - Autonomous Claude Code runner

Usage: ralph [options]

Options:
  help                  Show this help
  -p, --prompt FILE      Prompt file to use (default: RALPH_TASK.md)
  -e, --engine ENGINE    AI engine: claude or codex (default: claude)
  --codex-flags FLAGS    Extra flags passed to \`codex exec\` (default: --full-auto)
  --codex-flag FLAG      Repeatable: one flag per invocation (preserves quoting)
  -m, --max N            Max iterations, 0=unlimited (default: 0)
  -w, --wait N           Seconds between iterations (default: 5)
  -a, --attempts N       Max attempts before skipping task (default: 3)
  -t, --timeout N        Timeout per iteration in seconds (default: 600)
  --max-tools N          Max tool calls before considering stuck (default: 50)
  --max-stall N          Auto-exit after N consecutive non-productive iterations (default: 3, 0=disable)
  -j, --workers N        Number of parallel workers (default: 1, max: 16)
  --allowed-tools LIST   Comma-separated allowedTools for claude (default: unrestricted)
  --disallowed-tools LIST Comma-separated disallowedTools for claude (default: none)
  -c, --caffeinate       Prevent Mac from sleeping
  -l, --log [FILE]       Log output to file (default: ralph_TIMESTAMP.log)
  --log-format FORMAT    Log format: text or jsonl (default: text)
  -q, --quiet            Reduce output (keep banners + summaries)
  --ui MODE              UI mode: full, compact, minimal, dashboard
  --no-logo              Disable the ASCII logo header
  --no-status-line       Disable periodic status line updates
  --ascii                Force ASCII UI (no box-drawing)
  --no-iter-quote        Don't repeat a quote each iteration
  --bell-on-completion   Bell sound when iteration completes
  --bell-on-end          Bell sound when run ends (exit, max iter, Ctrl+C)
  --notify               Enable OS notifications (macOS/Linux/tmux)
  --no-exit-on-complete  Don't exit when EXIT_SIGNAL detected (keep looping)
  --no-title             Disable terminal title updates
  --no-resources         Disable docker resources section
  --no-wait-countdown    Disable animated wait countdown
  --show-attempts        Show current attempt tracking state
  --clear-attempts       Clear all attempt tracking (fresh start)
  -h, --help             Show this help

UI modes:
  full       Rich output: banners, progress bars, status lines (default)
  compact    One-line summaries per iteration (implies --quiet)
  minimal    Near-silent, essential output only (implies --quiet)
  dashboard  Live auto-refreshing terminal dashboard with progress bars

Keyboard shortcuts (during wait countdown / dashboard):
  q  Quit gracefully after current iteration
  s  Skip wait, start next iteration immediately
  p  Pause (press r to resume, q to quit)

Examples:
  ralph                         # Basic usage
  ralph --ui dashboard          # Live dashboard mode
  ralph -j 3                    # 3 parallel workers
  ralph -j 2 --ui dashboard     # Dashboard with parallel workers
  ralph --notify                # OS notifications on completion
  ralph --log --log-format jsonl # Structured event logging
  ralph -p my-task.md
  ralph --max 10 --wait 3
  ralph --caffeinate
  ralph --clear-attempts

EOF
}
