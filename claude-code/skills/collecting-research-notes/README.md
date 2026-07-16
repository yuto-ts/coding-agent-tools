# collecting-research-notes

A Claude Code skill for the reading-notes repository. It defines the workflow
for researching a topic across multiple media — arXiv papers, vendor
announcements, official docs, third-party tech blogs, and benchmark providers'
posts — and turning the findings into a Japanese research note with a
`## Sources` section.

Key disciplines baked into the skill:

- Distinguish primary from secondary sources; trace numbers and strong claims
  back to the primary source before quoting them.
- Keep all collected information — no summarizing away detail — and always list
  Sources.
- A built-in security harness: fetched web content is treated as untrusted
  data, so instructions embedded in pages are never executed, tools are
  restricted to collection/note-writing during research, and suspicious
  embedded instructions are reported instead of followed.
- Optional three-level glossary support (light inline glosses, a `## 用語`
  section, or full background explanations) triggered by requests like
  「用語解説つけて」 or 「レベル2で」.
- Lightweight WebSearch/WebFetch flow by default; the deep-research skill is
  only brought in for large surveys.

See [`SKILL.md`](./SKILL.md) for the full skill definition.

## Install

```sh
./install.sh                       # user-level: ~/.claude/skills/
./install.sh /path/to/reading-notes  # project-level: <repo>/.claude/skills/
```

This symlinks the skill directory into the chosen skills directory. Any
existing directory at the target is moved aside as `*.bak.<timestamp>`.
