# ctx-5h-monitor

CLI tool and statusline integration for monitoring the Claude Code 5-hour token window.

Displays estimated ceiling, percentage used, burn rate, and time until reset — directly in your terminal or in the Claude Code status bar.

## Output

CLI (`ctx`):

```
[Ceiling: High ~21.3M] 19% used (4.1M tokens) | Burn: 84k tok/min | Resets in 4h 38m
```

At the start of a new window (first ~2 minutes):

```
[Ceiling: calculating...] 0.3M tokens | Burn: 20k tok/min | Resets in 4h 58m
```

Statusline (when integrated):

```
nelsond20 | ~/project (main) | msg: 12 | claude-sonnet-4-6 | ctx: 45% | 5h: 19% [High] | reset: 4h 38m | next: 90k
```

## Ceiling levels

The 5-hour window limit varies daily based on Anthropic's load:

| Level | Range | Meaning |
|-------|-------|---------|
| **Low** | < 8M tokens | High-load day, tight budget |
| **Medium** | 8M – 18M tokens | Normal day |
| **High** | > 18M tokens | Good availability |

## Prerequisites

- [ccusage](https://github.com/ryoppippi/ccusage) — included with Claude Code CLI
- [jq](https://jqlang.github.io/jq/) — must be in PATH (`brew install jq`)
- macOS — uses BSD `date -jf` syntax, does not work on Linux

## Installation

### CLI only

```sh
git clone https://github.com/nelsond20/ctx-5h-monitor.git
cd ctx-5h-monitor
./install.sh
source ~/.zshrc   # or ~/.bashrc
```

Then run `ctx` while a Claude Code session is active.

### Statusline integration

The statusline patch adds `5h: 19% [High] | reset: 4h 38m` to your Claude Code status bar.

1. Open `statusline/patch.sh` — it contains three labeled sections
2. Open your `~/.claude/statusline-command.sh`
3. Copy each section into the corresponding location in your statusline script (the comments in `patch.sh` tell you exactly where)

## How it works

- **CLI** (`ctx-status.sh`): calls `ccusage blocks --active` directly for fresh data and reads the ceiling cache written by the statusline
- **Statusline** (`statusline/patch.sh`): caches ccusage output for 30 seconds to avoid slowing down the status bar; estimates the window ceiling from `totalTokens / five_hour_percentage` and writes it to `/tmp/ctx-ceiling.json`
- **Ceiling estimation**: requires >2% usage in the current window; shows `calculating...` below that threshold

## Notes

- The CLI depends on the ceiling cache written by the statusline integration. If the statusline hasn't run yet in the current window, `ctx` shows `[Ceiling: calculating...]`
- A full reset to 0% only happens if no tokens are used for 5 consecutive hours — the window is rolling, not session-based
