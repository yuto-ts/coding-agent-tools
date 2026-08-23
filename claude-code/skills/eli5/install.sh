#!/usr/bin/env bash
# Symlink this skill directory into a Claude Code skills directory.
#
# Usage:
#   ./install.sh              # user-level: ~/.claude/skills/collecting-research-notes
#   ./install.sh <repo-path>  # project-level: <repo-path>/.claude/skills/collecting-research-notes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_NAME="$(basename "$SCRIPT_DIR")"

if [ $# -ge 1 ]; then
  SKILLS_DIR="$1/.claude/skills"
else
  SKILLS_DIR="$HOME/.claude/skills"
fi
TARGET="$SKILLS_DIR/$SKILL_NAME"

mkdir -p "$SKILLS_DIR"

if [ -L "$TARGET" ]; then
  current="$(readlink "$TARGET")"
  if [ "$current" = "$SCRIPT_DIR" ]; then
    echo "Already linked: $TARGET -> $SCRIPT_DIR"
    exit 0
  fi
  echo "Replacing existing symlink: $TARGET (was -> $current)"
  rm "$TARGET"
elif [ -e "$TARGET" ]; then
  backup="${TARGET}.bak.$(date +%Y%m%d%H%M%S)"
  echo "Backing up existing directory: $TARGET -> $backup"
  mv "$TARGET" "$backup"
fi

ln -s "$SCRIPT_DIR" "$TARGET"
echo "Linked: $TARGET -> $SCRIPT_DIR"
