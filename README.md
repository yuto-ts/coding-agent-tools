# claude-code-tools

Personal toolkit for [Claude Code](https://docs.claude.com/en/docs/claude-code).
Each tool lives in its own directory so it can be installed independently and
moved easily across machines.

## Tools

| Directory | What it does |
|---|---|
| [`statusline/`](./statusline) | Status line script showing model name, context usage, and 5h / 7d rate-limit utilization |

## Conventions

- Every tool is self-contained: its own README and (when useful) `install.sh`.
- No personal/secret values in the repo — make them env vars or arguments.
- Primary target is macOS / zsh. Other platforms: see each tool's README.
