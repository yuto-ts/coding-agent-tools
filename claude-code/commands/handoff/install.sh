#!/usr/bin/env bash
# Symlink this slash command into a Claude Code commands directory.
#
# Usage:
#   ./install.sh              # user-level: ~/.claude/commands/cleanup-worktree.md
#   ./install.sh <repo-path>  # project-level: <repo-path>/.claude/commands/cleanup-worktree.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMAND_NAME="$(basename "$SCRIPT_DIR")"
SOURCE="$SCRIPT_DIR/$COMMAND_NAME.md"

if [ $# -ge 1 ]; then
  COMMANDS_DIR="$1/.claude/commands"
else
  COMMANDS_DIR="$HOME/.claude/commands"
fi
TARGET="$COMMANDS_DIR/$COMMAND_NAME.md"

mkdir -p "$COMMANDS_DIR"

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
