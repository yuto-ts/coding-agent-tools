# codex/statusline

A Codex usage/status script that displays the latest locally recorded Codex
token and rate-limit information.

Codex CLI does not currently expose a Claude Code-style `statusLine` hook that
runs a command with session JSON on stdin. This script reads Codex's local
session JSONL files instead:

```text
~/.codex/sessions/**/rollout-*.jsonl
```

It shows:

- Model and reasoning effort
- Approximate current context usage from the latest request input tokens
- Current Git branch when the recorded `cwd` is inside a Git repository
- Current and weekly rate-limit utilization
- Session input, cached input, output, and reasoning token totals

## Requirements

- macOS
- `bash`, `jq`
- Codex CLI session logs in `~/.codex/sessions`

## Install

```sh
./install.sh
```

This symlinks `~/.codex/statusline-command.sh` to the script in this repo.
Any existing file at the target is moved aside as `*.bak.<timestamp>`.

## Usage

Run manually:

```sh
bash ~/.codex/statusline-command.sh
```

Refresh periodically:

```sh
watch -n 5 bash ~/.codex/statusline-command.sh
```

Use the first line in tmux:

```sh
tmux set -g status-right '#(bash ~/.codex/statusline-command.sh | head -n 1)'
```

Pass a specific rollout file for debugging:

```sh
bash ~/.codex/statusline-command.sh ~/.codex/sessions/2026/05/05/rollout-....jsonl
```

## Example output

```text
gpt-5.5/medium │ ctx 16% (41k/258k) │ main │ plus
current ●○○○○○○○○○ 2% ↺3:21am
weekly  ○○○○○○○○○○ 3% ↺8:02am
session in 217k / cached 123k / out 2k / reasoning 599
```
