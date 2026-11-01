<!-- ai-writing-check: off -->
# humanizer

A Claude Code skill that drafts and revises prose (articles, READMEs, reports,
docs) against imoz's writing and editing rules, described in
<https://imoz.jp/scraps/202610_humanizer.html>.

```
/humanizer この README を推敲して
```

The skill reads the full rule file before editing, then runs the rule file's
post-writing checklist and repeats it until no concrete problem remains.

- Japanese: <https://imoz.jp/humanizer.ja.txt>
- English: <https://imoz.jp/humanizer.en.txt>

The rule text is not bundled here because no license is stated for it.
`fetch-rules.sh` downloads it into `~/.cache/humanizer/` on first use and
refreshes the copy after 7 days; if the download fails, the cached copy is used.

This skill complements the prompt-side rules in
[`claude-code/claude-md/`](../../claude-md) and the regex checks in
[`claude-code/hooks/ai-writing-check/`](../../hooks/ai-writing-check). Where
they conflict, CLAUDE.md wins.

## Install

```sh
./install.sh
```

Run it from a permanent checkout; the symlink points back into the repo.
