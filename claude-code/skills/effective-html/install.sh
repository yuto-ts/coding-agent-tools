#!/usr/bin/env bash
# Symlink every skill in this collection into a Claude Code skills directory.
#
# Usage:
#   ./install.sh              # user-level: ~/.claude/skills/<skill>
#   ./install.sh <repo-path>  # project-level: <repo-path>/.claude/skills/<skill>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -ge 1 ]; then
  SKILLS_DIR="$1/.claude/skills"
else
  SKILLS_DIR="$HOME/.claude/skills"
fi

mkdir -p "$SKILLS_DIR"

for skill_md in "$SCRIPT_DIR"/*/SKILL.md; do
  SKILL_DIR="$(dirname "$skill_md")"
  SKILL_NAME="$(basename "$SKILL_DIR")"
  TARGET="$SKILLS_DIR/$SKILL_NAME"

  if [ -L "$TARGET" ]; then
    current="$(readlink "$TARGET")"
    if [ "$current" = "$SKILL_DIR" ]; then
      echo "Already linked: $TARGET -> $SKILL_DIR"
      continue
    fi
    echo "Replacing existing symlink: $TARGET (was -> $current)"
    rm "$TARGET"
  elif [ -e "$TARGET" ]; then
    backup="${TARGET}.bak.$(date +%Y%m%d%H%M%S)"
    echo "Backing up existing directory: $TARGET -> $backup"
    mv "$TARGET" "$backup"
  fi

  ln -s "$SKILL_DIR" "$TARGET"
  echo "Linked: $TARGET -> $SKILL_DIR"
done
