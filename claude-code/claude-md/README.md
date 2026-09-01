# claude-md

User-level `CLAUDE.md` — Japanese writing-style rules that strip the "AI tone"
out of Claude Code's responses. Claude Code loads `~/.claude/CLAUDE.md` in every
session, so these rules apply across all projects.

The file covers five rules plus a short catch-all. Each one states what to
write, then shows one OK/NG pair for contrast:

1. Judgements as full sentences with a subject and a predicate; conditions and
   grounds attached whenever the claim is generalized.
2. The point stated directly — first sentence on topic, no contrast scaffolding
   (「単なる〜ではない」), no closing pleasantries, each point made once.
3. Degree expressed as measurements, counts, and sources; when nothing was
   measured, that fact is written instead of an adjective.
4. Length and structure matched to the question — 1–3 sentences for yes/no,
   headings and bullets only when there are actually 3+ parallel items.
5. Confidence stated explicitly: verified vs. read-in-the-code vs. guessed vs.
   unknown, rather than one uniform assertive tone.

The exhaustive list of NG expressions lives in
[`../hooks/ai-writing-check/rules.jsonl`](../hooks/ai-writing-check), not here.
The hook matches it line by line on every write and returns rewrite guidance,
so the always-loaded memory file stays a set of positive rules. `CLAUDE.md`
carries `<!-- ai-writing-check: off -->` because its own NG examples would
otherwise trip the hook.

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
