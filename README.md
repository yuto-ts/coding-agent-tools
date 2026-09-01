# coding-agent-tools

Personal toolkit for coding agents. Tools are grouped by agent first, then by
tool name, so each piece can be installed independently and moved easily across
machines.

## Tools

| Directory | What it does |
|---|---|
| [`claude-code/claude-md/`](./claude-code/claude-md) | User-level `CLAUDE.md` with Japanese writing-style rules that remove the "AI tone": no punchline assertions, no boilerplate rhetoric, numbers instead of intensifiers, length matched to the question, explicit confidence levels |
| [`claude-code/commands/cleanup/`](./claude-code/commands/cleanup) | Claude Code slash command for the 1 issue = 1 worktree workflow: tears down a merged branch's worktree, local/remote branch, and per-worktree resources, refusing to delete unmerged or uncommitted work |
| [`claude-code/commands/handoff/`](./claude-code/commands/handoff) | Claude Code slash command that turns the current session into a self-contained prompt for pasting into a different session — another Claude Code session, the Claude app, or claude.ai |
| [`claude-code/hooks/ai-writing-check/`](./claude-code/hooks/ai-writing-check) | Claude Code `PostToolUse`/`Stop` hooks that lint Japanese documents for "AI tone" right after every file write: regex NG rules paired with rewrite guidance, sentence-ending monotony/mixture checks, a completion gate that blocks until violations are rewritten, and an `/add-writing-rule` command for growing the rule set |
| [`claude-code/claude-remote-controller/`](./claude-code/claude-remote-controller) | Rust CLI (`claude-rc`) for Claude Code Remote Control: lists which projects are reachable from claude.ai/code or the mobile app, toggles them on and off, edits the auto-start list (Finder picker included), and backs the launchd job that starts them at login (`cargo install --git`, then `claude-rc setup`) |
| [`claude-code/skills/academic-slides/`](./claude-code/skills/academic-slides) | Claude Code skill for building presentation decks from a paper: HTML as the source of truth, figure extraction from the source PDF, a CSS-enforced design system, mechanical layout verification, and PDF / Google Slides output |
| [`claude-code/skills/collecting-research-notes/`](./claude-code/skills/collecting-research-notes) | Claude Code skill for the reading-notes repo: multi-source research workflow producing Japanese notes with primary-source verification, Sources sections, and a security harness for untrusted web content |
| [`claude-code/skills/effective-html/`](./claude-code/skills/effective-html) | Six Claude Code skills for self-contained single-file HTML artifacts, vendored from [plannotator/effective-html](https://github.com/plannotator/effective-html) (MIT): a routing `html` skill, `design-artifact` for subject-specific creative direction, and specialists for wireframes, interactive prototypes, plans, and diagrams |
| [`claude-code/skills/eli5/`](./claude-code/skills/eli5) | Claude Code skill that explains a topic to someone who knows nothing about it as an HTML artifact: a diagram type chosen per screen from six patterns, one idea and two sentences per screen, a single analogy with its breaking point stated, and answers written in the language the question was asked in |
| [`claude-code/skills/sanitize-artifacts/`](./claude-code/skills/sanitize-artifacts) | Claude Code skill that strips production residue from a generated artifact: sorts every statement into audience-facing content, invisible production guidance, or conversation residue, turns constraints into design decisions instead of disclaimers, and returns the revised deliverable with no process commentary |
| [`claude-code/statusline/`](./claude-code/statusline) | Claude Code `statusLine` script showing model name, context usage, and 5h / 7d rate-limit utilization |
| [`codex/statusline/`](./codex/statusline) | Codex usage/status script for tmux, starship, or manual `watch` usage |
| [`runcat/`](./runcat) | launchd job writing Claude Code / Codex rate-limit usage as [RunCat Neo custom metrics](https://zenn.dev/kyome/articles/eb4a9f664002ad) |

## Conventions

- Every tool is self-contained: its own README and (when useful) `install.sh`.
- No personal/secret values in the repo — make them env vars or arguments.
- Primary target is macOS / zsh. Other platforms: see each tool's README.
