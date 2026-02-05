# Ralph Loop

Autonomous agent runner for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and [Codex](https://openai.com/index/codex/).

Creates a loop where an AI agent picks tasks from a prompt file and executes them autonomously. Each iteration starts fresh with no context accumulation. Failed tasks are tracked and automatically skipped after configurable retries.

Named after Ralph Wiggum. *"I'm helping!"*

## Installation

```bash
git clone https://github.com/Yeine/ralph.git
cd ralph

# Option A: Run directly
bin/ralph --help

# Option B: Install system-wide
make install
```

### Dependencies

- `jq` - JSON processing
- `claude` (Claude Code CLI) or `codex` (OpenAI Codex CLI)
- `bash` 4.0+

## Quick Start

1. Create a `RALPH_TASK.md` file with your task instructions:

```markdown
# Task

Read TODO.md and find the first unchecked item.
Complete it, then mark it [x] done.

When done, output: DONE: <task description>
When picking a task, output: PICKING: <task description>
If all tasks are complete, output: EXIT_SIGNAL: true
If a task fails, output: ATTEMPT_FAILED: <task description>
```

2. Run ralph:

```bash
bin/ralph
```

Ralph will loop: pick a task, execute it, wait, repeat. Press `Ctrl+C` to stop.

## Usage

```
ralph [options]

Options:
  -p, --prompt FILE      Prompt file to use (default: RALPH_TASK.md)
  -e, --engine ENGINE    AI engine: claude or codex (default: claude)
  --codex-flags FLAGS    Extra flags for codex exec (default: --full-auto)
  -m, --max N            Max iterations, 0=unlimited (default: 0)
  -w, --wait N           Seconds between iterations (default: 5)
  -a, --attempts N       Max attempts before skipping task (default: 3)
  -t, --timeout N        Timeout per iteration in seconds (default: 600)
  --max-tools N          Max tool calls before stuck detection (default: 50)
  -j, --workers N        Parallel workers, 1-16 (default: 1)
  -c, --caffeinate       Prevent Mac from sleeping
  -l, --log [FILE]       Log output to file
  -q, --quiet            Reduce output
  --bell-on-completion   Bell when iteration completes
  --bell-on-end          Bell when run ends
  --no-exit-on-complete  Keep looping after EXIT_SIGNAL
  --show-attempts        Show attempt tracking state
  --clear-attempts       Reset all attempt tracking
  -h, --help             Show help
```

## Examples

```bash
# Basic usage
ralph

# Run 3 parallel workers
ralph -j 3

# Max 10 iterations with logging
ralph --max 10 --log

# Use Codex engine
ralph --engine codex

# Short wait, keep Mac awake
ralph -w 2 --caffeinate

# Reset failed task tracking
ralph --clear-attempts
```

## Signal Protocol

Ralph parses specific signal lines from the agent's output to track progress:

| Signal | Purpose |
|--------|---------|
| `PICKING: <task>` | Agent is starting work on a task |
| `DONE: <task>` | Task completed successfully |
| `MARKING COMPLETE: <task>` | Alternative completion signal |
| `ATTEMPT_FAILED: <task>` | Task explicitly failed |
| `EXIT_SIGNAL: true` | All tasks are complete, stop looping |

Include these signals in your prompt file so the agent knows to emit them.

## Parallel Mode

With `-j N`, ralph spawns N worker processes that coordinate via a shared claims file:

- Each worker picks a different task based on its worker ID
- Workers see what others are working on and avoid duplicates
- When any worker detects EXIT_SIGNAL, all workers stop
- Per-worker logs are created and streamed with colored prefixes

```bash
ralph -j 3 --max 5   # 3 workers, max 5 iterations each
```

## Architecture

```
bin/ralph          Entry point: CLI parsing, signal handling, dispatch
lib/
  colors.sh        Color definitions and TTY detection
  utils.sh         fmt_hms, task_hash, run_with_timeout, quotes
  ui.sh            Logging, horizontal rules, box drawing, banners
  lock.sh          Portable file locking (mkdir-based)
  attempts.sh      JSON-based attempt tracking
  claims.sh        Worker claims for parallel coordination
  workers.sh       Worker state and counter management
  engine.sh        Claude/Codex execution and JSONL parsing
  iteration.sh     Core iteration logic
  loop.sh          Main loop, worker subprocess, parallel coordinator
```

## Testing

```bash
# One-time: initialize test submodules
git submodule update --init --recursive

# Run tests
make test

# Run with verbose output
make test-verbose

# Lint all sources
make lint
```

## License

MIT
