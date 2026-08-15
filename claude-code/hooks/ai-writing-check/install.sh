#!/usr/bin/env bash
# Install the ai-writing-check hook:
#   1. Symlink this directory to ~/.claude/hooks/ai-writing-check
#   2. Symlink add-writing-rule.md to ~/.claude/commands/add-writing-rule.md
#   3. Register the PostToolUse / Stop hooks in ~/.claude/settings.json
#      (idempotent; the existing file is backed up first)
#
# Usage:
#   ./install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
HOOK_TARGET="$CLAUDE_DIR/hooks/ai-writing-check"
COMMAND_TARGET="$CLAUDE_DIR/commands/add-writing-rule.md"
SETTINGS="$CLAUDE_DIR/settings.json"

link() {
  local source="$1" target="$2"
  if [ -L "$target" ]; then
    local current
    current="$(readlink "$target")"
    if [ "$current" = "$source" ]; then
      echo "Already linked: $target -> $source"
      return
    fi
    echo "Replacing existing symlink: $target (was -> $current)"
    rm "$target"
  elif [ -e "$target" ]; then
    local backup="${target}.bak.$(date +%Y%m%d%H%M%S)"
    echo "Backing up existing file: $target -> $backup"
    mv "$target" "$backup"
  fi
  ln -s "$source" "$target"
  echo "Linked: $target -> $source"
}

mkdir -p "$CLAUDE_DIR/hooks" "$CLAUDE_DIR/commands"
link "$SCRIPT_DIR" "$HOOK_TARGET"
link "$SCRIPT_DIR/add-writing-rule.md" "$COMMAND_TARGET"

# --- settings.json への hook 登録(無ければ追記、あれば何もしない) ---
python3 - "$SETTINGS" <<'PYEOF'
import json, os, shutil, sys, time

settings_path = sys.argv[1]
check = 'python3 "$HOME/.claude/hooks/ai-writing-check/check.py"'
pre_entry = {
    "matcher": "Write|Edit|MultiEdit",
    "hooks": [{"type": "command", "command": f"{check} --hook pre-tool-use"}],
}
post_entry = {
    "matcher": "Write|Edit|MultiEdit",
    "hooks": [{"type": "command", "command": f"{check} --hook post-tool-use"}],
}
stop_entry = {
    "hooks": [{"type": "command", "command": f"{check} --hook stop"}],
}

settings = {}
if os.path.isfile(settings_path):
    with open(settings_path, encoding="utf-8") as f:
        settings = json.load(f)

hooks = settings.setdefault("hooks", {})
changed = False
for event, entry in (("PreToolUse", pre_entry),
                     ("PostToolUse", post_entry),
                     ("Stop", stop_entry)):
    entries = hooks.setdefault(event, [])
    want = entry["hooks"][0]["command"]
    # 既存コマンド文字列と直接比べる(json.dumps 経由だと引用符がエスケープされて一致しない)
    registered = any(h.get("command") == want
                     for e in entries for h in e.get("hooks", []))
    if not registered:
        entries.append(entry)
        changed = True

if changed:
    if os.path.isfile(settings_path):
        backup = f"{settings_path}.bak.{time.strftime('%Y%m%d%H%M%S')}"
        shutil.copy2(settings_path, backup)
        print(f"Backed up: {backup}")
    with open(settings_path, "w", encoding="utf-8") as f:
        json.dump(settings, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"Registered PostToolUse/Stop hooks in {settings_path}")
else:
    print(f"Hooks already registered in {settings_path}")
PYEOF

echo "Done. Restart running Claude Code sessions to pick up the hooks."
