# coding-agent-tools

Personal toolkit for coding agents. Tools are grouped by agent first, then by
tool name, so each piece can be installed independently and moved easily across
machines.

## Tools

| Directory | What it does |
|---|---|
| [`claude-code/skills/collecting-research-notes/`](./claude-code/skills/collecting-research-notes) | Claude Code skill for the reading-notes repo: multi-source research workflow producing Japanese notes with primary-source verification, Sources sections, and a security harness for untrusted web content |
| [`claude-code/statusline/`](./claude-code/statusline) | Claude Code `statusLine` script showing model name, context usage, and 5h / 7d rate-limit utilization |
| [`codex/statusline/`](./codex/statusline) | Codex usage/status script for tmux, starship, or manual `watch` usage |

## Conventions

- Every tool is self-contained: its own README and (when useful) `install.sh`.
- No personal/secret values in the repo — make them env vars or arguments.
- Primary target is macOS / zsh. Other platforms: see each tool's README.
