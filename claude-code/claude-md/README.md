# claude-md

User-level `CLAUDE.md` — Japanese writing-style rules that strip the "AI tone"
out of Claude Code's responses. Claude Code loads `~/.claude/CLAUDE.md` in every
session, so these rules apply across all projects.

The file covers five rules plus a short catch-all:

1. No punchline-style assertions (体言止めの言い切り) or ungrounded
   generalizations (「常に」「必ず」).
2. No boilerplate rhetoric — the「単なる〜ではない」contrast pattern, opening
   flattery, closing pleasantries, or saying the same thing three times.
3. Facts and numbers instead of intensifiers (「大幅に」「堅牢な」); if nothing
   was measured, say so instead of reaching for an adjective.
4. Length and structure matched to the question — 1–3 sentences for yes/no,
   headings and bullets only when there are actually 3+ parallel items.
5. Confidence stated explicitly: verified vs. read-in-the-code vs. guessed vs.
   unknown, rather than one uniform assertive tone.

## Install

```sh
./install.sh                  # user-level: ~/.claude/CLAUDE.md
./install.sh /path/to/repo    # project-level: <repo>/CLAUDE.md
```

This symlinks `CLAUDE.md` into the chosen location. Any existing file at the
target is moved aside as `CLAUDE.md.bak.<timestamp>`.

Because the target is a single fixed path, the user-level install replaces the
whole `~/.claude/CLAUDE.md`. To keep other user-level instructions alongside
these rules, install project-level instead, or `@`-import this file from your
own `~/.claude/CLAUDE.md`:

```md
@~/prog/coding-agent-tools/claude-code/claude-md/CLAUDE.md
```
