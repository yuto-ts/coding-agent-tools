# handoff

A Claude Code slash command that turns the current session into a self-contained
prompt you can paste into a different session — another Claude Code session,
the Claude app, or claude.ai — to hand off the work.

```
/handoff                          # summarize the session as-is
/handoff focus on the API design  # steer what to include
/handoff file                     # force output to a Markdown file
/handoff issue                    # force output to a GitHub Issue
/handoff inline                   # force output inline in the chat
```

The generated prompt assumes the receiving session knows nothing about this
conversation:

- **Self-contained.** No "as discussed above" references — all necessary
  context (goal, decisions made and why, current state, relevant file paths /
  URLs / commands) is written into the prompt itself.
- **No noise.** Failed attempts and back-and-forth are left out, except a
  one-line mention when they affect the conclusion.
- **Three output destinations.** `inline` prints a copy-paste-ready fenced
  code block; `file` writes to `.claude/handoff/<timestamp>-<slug>.md` and
  hands back the absolute path; `issue` opens a GitHub Issue after showing
  the title/body for approval. With no destination given, it picks based on
  length — short summaries go inline, longer ones go to a file.
- **Doesn't assume file access.** Since the target session may not be Claude
  Code (e.g. the Claude app), relevant code snippets or config are inlined
  rather than referenced by path.

## Install

```sh
./install.sh                  # user-level: ~/.claude/commands/
./install.sh /path/to/repo    # project-level: <repo>/.claude/commands/
```

This symlinks `handoff.md` into the chosen commands directory. Any existing
file at the target is moved aside as `*.bak.<timestamp>`.
