#!/usr/bin/env bash
# Fetch imoz's humanizer rule files into a local cache and print the path.
#
# The rule text is not bundled in this repository (no license is stated for
# it); it is downloaded from the author's site on first use and refreshed
# when the cached copy is older than 7 days.
#
# Usage:
#   ./fetch-rules.sh ja   # -> ~/.cache/humanizer/humanizer.ja.txt
#   ./fetch-rules.sh en   # -> ~/.cache/humanizer/humanizer.en.txt
set -euo pipefail

LANG_CODE="${1:-ja}"
case "$LANG_CODE" in
  ja|en) ;;
  *) echo "usage: $0 ja|en" >&2; exit 1 ;;
esac

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/humanizer"
FILE="$CACHE_DIR/humanizer.$LANG_CODE.txt"
URL="https://imoz.jp/humanizer.$LANG_CODE.txt"

mkdir -p "$CACHE_DIR"

if [ ! -s "$FILE" ] || [ -n "$(find "$FILE" -mtime +7 2>/dev/null)" ]; then
  tmp="$(mktemp "$CACHE_DIR/.download.XXXXXX")"
  if curl -fsSL --max-time 30 -o "$tmp" "$URL" && [ -s "$tmp" ]; then
    mv "$tmp" "$FILE"
  else
    rm -f "$tmp"
    if [ -s "$FILE" ]; then
      echo "warning: download failed, using cached copy" >&2
    else
      echo "error: could not download $URL" >&2
      exit 1
    fi
  fi
fi

echo "$FILE"
