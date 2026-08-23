# sanitize-artifacts

A Claude Code skill that strips production residue out of a generated artifact,
so the deliverable reads as if it had been designed for its audience rather than
assembled from the conversation that produced it.

Iterative prompting leaves traces: "As requested...", "This guide does not use
Git or Homebrew", a prompt example that quietly became the topic, disclaimers
that only made sense mid-conversation. The skill treats all of that as
production context and decides, statement by statement, whether it belongs in
the artifact at all.

The core move is a three-way classification of everything the conversation
produced:

1. Content the artifact's audience genuinely needs — keep it.
2. Production guidance — reflect it through structure, tone, scope, defaults,
   naming, and design choices, but never state it.
3. Conversation residue — remove it.

Constraints stay invisible. "This document does not use Git" becomes "Share the
project folder using Google Drive". "Beginner-friendly" becomes pacing and
definitions, not a disclaimer. An example given to communicate intent is
diagnostic material, so it is used to infer the level of abstraction, audience,
and tone rather than copied into the deliverable.

The skill also fixes what the output looks like: return the revised artifact
itself, with no "Here is the sanitized version" preamble and no report of what
was removed unless the user asked for one.

See [`SKILL.md`](./SKILL.md) for the full definition, including the 10-point
inspection checklist used before handing the artifact over.

## Install

```sh
./install.sh                     # user-level: ~/.claude/skills/
./install.sh /path/to/some-repo  # project-level: <repo>/.claude/skills/
```

This symlinks the skill directory into the chosen skills directory. Any
existing directory at the target is moved aside as `*.bak.<timestamp>`.

## Origin

Vendored as-is from
[kotek-7/dotfiles](https://github.com/kotek-7/dotfiles/blob/main/dot_agents/skills/sanitize-artifacts/SKILL.md).
