# effective-html

Six Claude Code skills for building self-contained single-file HTML artifacts
— wireframes, mockups, interactive prototypes, plans, and diagrams — vendored
from [plannotator/effective-html](https://github.com/plannotator/effective-html)
(MIT, see [LICENSE](./LICENSE)), snapshot of commit `d95debb`.

## Skills

| Skill | Use it for |
|---|---|
| [`html/`](./html) | Broad HTML requests — reports, explainers, presentations, landing pages, tools. The collection's only implicit router: it dispatches clear wireframe / prototype / plan / diagram requests to the specialists below |
| [`design-artifact/`](./design-artifact) | Subject-specific creative direction (palette, type, layout) for any HTML artifact, aimed at avoiding a generic AI-generated look |
| [`html-wireframe/`](./html-wireframe) | Low-fidelity layouts that test content, hierarchy, navigation, and flows — intentionally unfinished so review focuses on structure |
| [`html-prototype/`](./html-prototype) | Working prototypes with realistic states, interaction, keyboard support, and responsive behavior; static mockups are a fidelity mode of this skill |
| [`html-plan/`](./html-plan) | Plans, roadmaps, and rollout sequences that preserve source commitments |
| [`html-diagram/`](./html-diagram) | Architecture, sequence, process, state, hierarchy, and timeline diagrams |

The five specialists activate only when invoked explicitly or routed to by
`html`. Every artifact is expected to be responsive, accessible,
self-contained, and verified in a browser.

## Install

Symlinks each of the six skill directories into a Claude Code skills
directory:

```
./install.sh              # user-level: ~/.claude/skills/<skill>
./install.sh <repo-path>  # project-level: <repo-path>/.claude/skills/<skill>
```

## Updating from upstream

The vendored copy is a plain snapshot — no submodule. To update, copy the
`skills/` subdirectories and `LICENSE` from a fresh clone of
plannotator/effective-html over this directory and record the new upstream
commit in this README. Upstream's `agents/openai.yaml` files (Codex metadata)
are kept so a future Codex setup can reuse the same copy; Claude Code ignores
them.
