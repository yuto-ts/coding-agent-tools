#!/usr/bin/env bash
# Symlink this CLAUDE.md into a Claude Code memory location.
#
# Usage:
#   ./install.sh              # user-level: ~/.claude/CLAUDE.md
#   ./install.sh <repo-path>  # project-level: <repo-path>/CLAUDE.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/CLAUDE.md"

if [ $# -ge 1 ]; then
  TARGET_DIR="$1"
else
  TARGET_DIR="$HOME/.claude"
fi
TARGET="$TARGET_DIR/CLAUDE.md"

mkdir -p "$TARGET_DIR"

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
  echo "Backing up existing file: $TARGET -> $backup"
  mv "$TARGET" "$backup"
fi

ln -s "$SOURCE" "$TARGET"
echo "Linked: $TARGET -> $SOURCE"
