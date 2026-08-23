#!/usr/bin/env bash
# Symlink this plugin's eli5 skill into a Claude Code skills directory.
#
# Use this when you want the skill without going through a marketplace.
# See README.md for the plugin install route.
#
# Usage:
#   ./install.sh              # user-level: ~/.claude/skills/eli5
#   ./install.sh <repo-path>  # project-level: <repo-path>/.claude/skills/eli5
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/skills/eli5"
SKILL_NAME="eli5"

if [ $# -ge 1 ]; then
  SKILLS_DIR="$1/.claude/skills"
else
  SKILLS_DIR="$HOME/.claude/skills"
fi
TARGET="$SKILLS_DIR/$SKILL_NAME"

mkdir -p "$SKILLS_DIR"

if [ -L "$TARGET" ]; then
  current="$(readlink "$TARGET")"
  if [ "$current" = "$SOURCE" ]; then
    echo "Already linked: $TARGET -> $SOURCE"
    exit 0
  fi
  echo "Replacing existing symlink: $TARGET (was -> $current)"
  rm "$TARGET"
elif [ -e "$TARGET" ]; then
  backup="${TARGET}.bak.$(date +%Y%m%d%H%M%S)"
  echo "Backing up existing directory: $TARGET -> $backup"
  mv "$TARGET" "$backup"
fi

ln -s "$SOURCE" "$TARGET"
echo "Linked: $TARGET -> $SOURCE"
