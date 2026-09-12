# eli5

A Claude Code skill that explains a topic to someone who knows nothing about
it, as an HTML artifact built from big pictures and few words.

```
/eli5 DNS はどうやって名前を IP に変えているのか
/eli5 how does the TLS handshake work
```

It started as a rewrite of the [`eli5`](https://github.com/anthropics/claude-plugins-community/tree/main/eli5)
community plugin (a three-line prompt) and differs from it in four ways:

- **Answers in the language of the question.** Japanese in, Japanese out.
  Technical terms and proper nouns stay in their original form — `DNS` is never
  translated into a paraphrase.
- **Picks a diagram type before drawing.** Six types (flow, cutaway,
  before/after, analogy, exploded view, quantity comparison) with a stated use
  case for each, as the common starting set rather than a closed menu. A screen
  no diagram fits at all is a screen holding two ideas at once.
- **Caps the budget per screen.** One idea, a heading of 12 Japanese
  characters or 6 English words, two sentences, one diagram, six labels inside
  it. Over budget means splitting the screen, not shrinking the prose.
- **Keeps the analogy honest.** One analogy per explanation, no
  anthropomorphizing, and a closing line naming where the analogy breaks down.

Simplification is allowed to drop detail, never to state something false. The
closing screen lists up to three things left out.

See [`SKILL.md`](./SKILL.md) for the full skill definition.

## Install

```sh
./install.sh                    # user-level: ~/.claude/skills/eli5
./install.sh /path/to/some-repo # project-level: <repo>/.claude/skills/eli5
```

This symlinks the skill directory into the chosen skills directory. Any
existing directory at the target is moved aside as `*.bak.<timestamp>`.

## Name clash with the community plugin

This skill and the `eli5@claude-community` plugin both register a skill named
`eli5`, so `/eli5` becomes ambiguous when both are installed. Uninstall the
community plugin first:

```sh
/plugin uninstall eli5@claude-community
```
