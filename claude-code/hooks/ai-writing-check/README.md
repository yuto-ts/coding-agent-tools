<!-- ai-writing-check: off -->
# ai-writing-check

Claude Code hooks that lint Japanese documents for "AI tone" right after every
file write, and make the agent rewrite the offending sentences — the
machine-checked counterpart to the prompt-side rules in
[`claude-code/claude-md/`](../../claude-md).

## How it works

1. **PostToolUse** — after every `Write` / `Edit` / `MultiEdit`, the written
   file is matched against the NG rules in `rules.jsonl` plus document-level
   checks. On a hit, the hook exits with code 2 and the warning goes back to
   the agent, which rewrites and gets re-checked on the next write.
2. **Stop** — when the session is about to end, every file edited in the
   session (recovered from the transcript) is re-checked. Remaining violations
   block completion until they are rewritten.

The warning explicitly forbids swapping just the flagged word: the agent is
told to rewrite the whole sentence containing the match, because word-level
substitution leaves the same problem in a different form.

### Checks

- **NG rules** (`rules.jsonl`) — regex matches, one rule per line. Every rule
  carries a `good` field: rewrite guidance ("こう書き直す") returned together
  with the match, so the agent knows what to write instead of just what to
  avoid. Ships with 40 starter rules covering six categories: punchline
  assertions, unrequested contrast, predicates that skip the actual effect,
  boilerplate openers/closers, intensifiers with no numbers behind them, and
  rhetorical clichés — see `rules.jsonl` for the concrete patterns, drawn from
  the rules in [`claude-code/claude-md/`](../../claude-md).
- **Sentence-ending runs** — the same polite ending (ます/です/ました…)
  repeated for 3+ consecutive sentences. This can't be caught per-sentence;
  the script counts endings across the document.
- **Style mixture** — です・ます調 and 常体 both present in one document
  (each 2+ sentences), reported with the ending distribution.

Only `.md` / `.mdx` / `.txt` files containing Japanese are checked. Code
fences, inline code, blockquotes, and 「」-quoted spans are excluded; bullet
lists are exempt from the run check (uniform endings are normal there).

## Install

```sh
./install.sh
```

This symlinks the directory to `~/.claude/hooks/ai-writing-check`, the
`/add-writing-rule` command to `~/.claude/commands/`, and registers the hooks
in `~/.claude/settings.json` (idempotent; the previous file is backed up as
`settings.json.bak.<timestamp>`). Run it from a permanent checkout, not a
temporary worktree — the symlinks point back into the repo. Restart running
sessions afterwards.

Registered hook entries:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [{ "type": "command", "command": "python3 \"$HOME/.claude/hooks/ai-writing-check/check.py\" --hook post-tool-use" }]
      }
    ],
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "python3 \"$HOME/.claude/hooks/ai-writing-check/check.py\" --hook stop" }]
      }
    ]
  }
}
```

## Growing the rule set

The starter set is deliberately small; the intended workflow is to add a rule
every time you correct the agent's Japanese, so the machine makes the next
correction for you:

- `/add-writing-rule <NG表現> [補足]` — the bundled slash command finds the
  rules file, checks for duplicates, writes a regex narrowed with particles
  and conjugations, attaches a `good` rewrite pattern, and verifies detection
  before reporting.
- Manually: append one JSON line to `rules.jsonl`
  (`{"id": ..., "pattern": ..., "good": ...}`; `#` lines are comments), then
  test with `python3 check.py <file>`.

Per-project rules can be added at `.claude/ai-writing-rules.jsonl` in the
project root — loaded in addition to the shared set when Claude Code sets
`CLAUDE_PROJECT_DIR`.

## Opting a file out

Files that legitimately quote NG phrases (style guides, this README) opt out
with a marker anywhere in the file, e.g. as an HTML comment:

```md
<!-- ai-writing-check: off -->
```

## Manual runs

```sh
python3 check.py path/to/doc.md            # exit 1 + report if violations
```

Useful when testing new rules.

## Requirements

- `python3` (standard library only)
- Claude Code with hooks support (`PostToolUse` / `Stop`)

## Limitations

- Regexes are matched per line; patterns spanning lines are not detected.
- Metaphor-overuse detection (重ね使い) from the original workflow is not
  implemented.
- The Stop gate re-checks any eligible file the session wrote, including
  scratch drafts; add the off marker to drafts you don't want gated.
