#!/bin/bash
# スライドHTML -> PDF (Chrome headless)
#   bash build_pdf.sh deck.html [deck.pdf]
set -euo pipefail

HTML="${1:?使い方: build_pdf.sh <html> [pdf]}"
OUT="${2:-${HTML%.html}.pdf}"

for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "/Applications/Chromium.app/Contents/MacOS/Chromium" \
         "/usr/bin/google-chrome" "/usr/bin/chromium" "/usr/bin/chromium-browser"; do
  [ -x "$c" ] && CHROME="$c" && break
done
[ -n "${CHROME:-}" ] || { echo "Chrome / Chromium が見つかりません" >&2; exit 1; }

HTML_ABS="$(cd "$(dirname "$HTML")" && pwd)/$(basename "$HTML")"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

"$CHROME" --headless --disable-gpu --no-sandbox \
  --print-to-pdf="$OUT_ABS" \
  --no-pdf-header-footer \
  --virtual-time-budget=15000 \
  "file://$HTML_ABS" 2>/dev/null

echo "生成: $OUT_ABS"
# ページ数と用紙サイズが想定どおりか確認する(16:9 なら 960x540 pts)
command -v pdfinfo >/dev/null && pdfinfo "$OUT_ABS" | grep -E "Pages|Page size" || true
