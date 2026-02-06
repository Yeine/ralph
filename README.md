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
  --log-format FORMAT    Log format: text or jsonl (default: text)
  -q, --quiet            Reduce output (keep banners + summaries)
  --ui MODE              UI mode: full, compact, minimal, dashboard
  --no-logo              Disable the ASCII logo header
  --no-status-line       Disable periodic status line updates
  --ascii                Force ASCII UI (no box-drawing)
  --no-iter-quote        Don't repeat a quote each iteration
  --bell-on-completion   Bell when iteration completes
  --bell-on-end          Bell when run ends
  --notify               Enable OS notifications (macOS/Linux/tmux)
  --no-exit-on-complete  Keep looping after EXIT_SIGNAL
  --no-title             Disable terminal title updates
  --no-resources         Disable docker resources section
  --no-wait-countdown    Disable animated wait countdown
  --allowed-tools LIST   Comma-separated allowedTools for claude
  --disallowed-tools LIST Comma-separated disallowedTools for claude
  --show-attempts        Show attempt tracking state
  --clear-attempts       Reset all attempt tracking
  -h, --help             Show help
```

## Examples

```bash
# Basic usage
ralph

# Help
ralph help

# Live dashboard mode
ralph --ui dashboard

# Dashboard with parallel workers
ralph -j 3 --ui dashboard

# Run 3 parallel workers
ralph -j 3

# Max 10 iterations with structured logging
ralph --max 10 --log --log-format jsonl

# OS notifications on task completion
ralph --notify

# Use Codex engine
ralph --engine codex

# Short wait, keep Mac awake
ralph -w 2 --caffeinate

# Reset failed task tracking
ralph --clear-attempts
```

## UI Modes

### Full (default)
Rich output with box-drawn banners, progress bars, spinners, status lines, and result cards. Best for interactive terminal use.

```bash
ralph --ui full
```

### Dashboard
Live auto-refreshing terminal display using alternate screen buffer. Shows real-time progress bars, health metrics, iteration history trail, and worker status panel. Keyboard shortcuts active.

```bash
ralph --ui dashboard
```

### Compact
One-line summaries per iteration. Implies `--quiet`. Good for CI or log-only use.

```bash
ralph --ui compact --no-status-line --no-logo
```

### Minimal
Near-silent. Only essential output. Implies `--quiet`.

```bash
ralph --ui minimal
```

Notes:
- Use `--ascii` to force plain ASCII if your terminal does not support box drawing.
- Progress bars, spinners, and history trails work in both Unicode and ASCII modes.

## Visual Features

### Progress Bars
Time elapsed and tool call counts display as color-coded gauges that transition green to yellow to red as thresholds approach:

```
[████████████░░░░░░░░] 58%  348s/600s
[██████░░░░░░░░░░░░░░] 30%  15/50
```

### Spinner
A braille animation (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`) on the status line signals the engine is alive. Falls back to `|/-\` in ASCII mode.

### Iteration History Trail
A compact timeline of past iterations for at-a-glance run health:

```
History: ✓✓✓✗✓✓⊘✓✓✗✓✓ (12 iterations)
```

### Error Context Boxes
Failed iterations display structured diagnostic boxes:

```
╭─ FAILURE DETAILS ──────────────────────────╮
│ Task:    refactor-auth-middleware           │
│ Reason:  timeout (600s exceeded)           │
│ Attempt: 2/3                               │
├────────────────────────────────────────────┤
│ Signals:                                   │
│   PICKING: refactor-auth-middleware        │
│   >>> Bash: npm test                       │
│   ATTEMPT_FAILED: refactor-auth-middleware │
╰────────────────────────────────────────────╯
```

### Health & Rate Metrics
Run summary includes health percentage (completed vs failed ratio) and throughput rate (tasks per hour).

### Smarter Terminal Title
Window title updates with live state summary including completion counts and current task. Supports iTerm2 badge via OSC 1337.

## OS Notifications

With `--notify`, ralph sends desktop notifications on:
- Task completion
- Task failure
- Run end (with summary)

Supports:
- **macOS**: `osascript` (native notification center)
- **Linux**: `notify-send` (libnotify)
- **tmux**: `tmux display-message`

## Structured Logging

With `--log-format jsonl`, events are logged as JSON lines for post-run analysis:

```json
{"ts":"2024-01-15T14:23:45Z","event":"iteration_end","iteration":12,"status":"OK","task":"auth","elapsed":142,"tools":28}
```

Events logged: `run_start`, `iteration_start`, `iteration_end`, `task_skipped`, `run_end`.

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
- In dashboard mode, a worker status panel shows all workers

```bash
ralph -j 3 --max 5            # 3 workers, max 5 iterations each
ralph -j 4 --ui dashboard     # 4 workers with live dashboard
```

## Architecture

```
bin/ralph          Entry point: CLI parsing, signal handling, dispatch
lib/
  colors.sh        Color definitions and TTY detection
  utils.sh         fmt_hms, task_hash, run_with_timeout, quotes
  ui.sh            Logging, box drawing, banners, spinners, progress bars,
                   dashboard, worker panel, error boxes, history trail
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
