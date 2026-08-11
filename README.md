# coding-agent-tools

Personal toolkit for coding agents. Tools are grouped by agent first, then by
tool name, so each piece can be installed independently and moved easily across
machines.

## Tools

| Directory | What it does |
|---|---|
| [`claude-code/commands/cleanup-worktree/`](./claude-code/commands/cleanup-worktree) | Claude Code slash command for the 1 issue = 1 worktree workflow: tears down a merged branch's worktree, local/remote branch, and per-worktree resources, refusing to delete unmerged or uncommitted work |
| [`claude-code/skills/academic-slides/`](./claude-code/skills/academic-slides) | Claude Code skill for building presentation decks from a paper: HTML as the source of truth, figure extraction from the source PDF, a CSS-enforced design system, mechanical layout verification, and PDF / Google Slides output |
| [`claude-code/skills/collecting-research-notes/`](./claude-code/skills/collecting-research-notes) | Claude Code skill for the reading-notes repo: multi-source research workflow producing Japanese notes with primary-source verification, Sources sections, and a security harness for untrusted web content |
| [`claude-code/statusline/`](./claude-code/statusline) | Claude Code `statusLine` script showing model name, context usage, and 5h / 7d rate-limit utilization |
| [`codex/statusline/`](./codex/statusline) | Codex usage/status script for tmux, starship, or manual `watch` usage |
| [`runcat/`](./runcat) | launchd job writing Claude Code / Codex rate-limit usage as [RunCat Neo custom metrics](https://zenn.dev/kyome/articles/eb4a9f664002ad) |

## Conventions

- Every tool is self-contained: its own README and (when useful) `install.sh`.
- No personal/secret values in the repo — make them env vars or arguments.
- Primary target is macOS / zsh. Other platforms: see each tool's README.
