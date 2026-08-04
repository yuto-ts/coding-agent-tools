#!/bin/bash
# スライドHTML -> pptx (Google Slides で編集可能な形式)
#   bash export_pptx.sh deck.html [deck.pptx]
#
# 手作業でレイアウトを組み直すのではなく、ブラウザが計算した実座標を
# 抽出して python-pptx でテキストボックス化する。HTMLを直して再実行すれば
# pptx も追随するので、二重管理にならない。
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
HTML="${1:?使い方: export_pptx.sh <html> [pptx]}"
OUT="${2:-${HTML%.html}.pptx}"

for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
         "/Applications/Chromium.app/Contents/MacOS/Chromium" \
         "/usr/bin/google-chrome" "/usr/bin/chromium" "/usr/bin/chromium-browser"; do
  [ -x "$c" ] && CHROME="$c" && break
done
[ -n "${CHROME:-}" ] || { echo "Chrome / Chromium が見つかりません" >&2; exit 1; }

python3 -c "import pptx" 2>/dev/null || { echo "python-pptx が必要です: pip3 install python-pptx" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 抽出スクリプトをインラインで埋め込む(file:// の外部スクリプト読み込みを避ける)
HTML="$HTML" WORK="$WORK" JS="$HERE/layout_dump.js" python3 - <<'PY'
import os, re
html_path = os.environ['HTML']
base = os.path.dirname(os.path.abspath(html_path))
src = open(html_path, encoding='utf-8').read()
src = re.sub(r'src="(?!https?:|/|data:)', 'src="' + base + '/', src)
src = src.replace('</body>', '<script>\n' + open(os.environ['JS'], encoding='utf-8').read() + '\n</script>\n</body>')
open(os.path.join(os.environ['WORK'], 'dump.html'), 'w', encoding='utf-8').write(src)
PY

echo "レイアウトを抽出中..."
"$CHROME" --headless --disable-gpu --no-sandbox \
  --virtual-time-budget=15000 --dump-dom \
  "file://$WORK/dump.html" > "$WORK/dom.html" 2>/dev/null

WORK="$WORK" python3 - <<'PY'
import html as H, json, os, re, sys
work = os.environ['WORK']
dom = open(os.path.join(work, 'dom.html'), encoding='utf-8').read()
cands = re.findall(r'<pre id="layout-json">(.*?)</pre>', dom, re.S)
if not cands:
    sys.exit('レイアウトJSONを回収できませんでした')
data = json.loads(H.unescape(max(cands, key=len)))
json.dump(data, open(os.path.join(work, 'layout.json'), 'w', encoding='utf-8'), ensure_ascii=False)
print(f"  {len(data)} ページ分のレイアウトを取得")
PY

echo "pptx を生成中..."
python3 "$HERE/export_pptx.py" "$WORK/layout.json" "$OUT"
