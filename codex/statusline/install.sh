#!/usr/bin/env bash
# Symlink statusline-command.sh into ~/.codex/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/statusline-command.sh"
TARGET="$HOME/.codex/statusline-command.sh"

mkdir -p "$HOME/.codex"

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
chmod +x "$SOURCE"

echo "Linked: $TARGET -> $SOURCE"
echo
echo "Examples:"
echo "  watch -n 5 bash ~/.codex/statusline-command.sh"
echo "  tmux set -g status-right '#(bash ~/.codex/statusline-command.sh | head -n 1)'"
