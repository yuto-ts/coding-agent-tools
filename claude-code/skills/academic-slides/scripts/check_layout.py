#!/usr/bin/env python3
"""スライドHTMLの全ページを一括検査する(はみ出し・情報の充填率)。

  python3 check_layout.py deck.html
  python3 check_layout.py deck.html --json      # 機械可読な出力

PDFを画像化して目視で確認するより速く、確実。ヘッドレスブラウザで全要素の
座標を実測し、スライド枠からのはみ出しと本文領域の充填率を返す。

  overflow  枠外にはみ出した量。PDFでは黙って切れるため、出たら必ず直す
  fill      本文領域に対する内容の高さの割合。本編は 70〜95% が目安
"""
import argparse
import html
import json
import os
import re
import subprocess
import sys
import tempfile

CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "/usr/bin/google-chrome",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
]

PROBE_JS = r"""
(function () {
  function measure() {
    const rows = [];
    document.querySelectorAll('section.slide').forEach((s, i) => {
      const sr = s.getBoundingClientRect();
      const body = s.querySelector('.body');
      let maxBottom = 0, maxRight = 0, minTop = 1e9, minLeft = 1e9;
      const scope = body || s;
      scope.querySelectorAll('*').forEach(el => {
        const cs = getComputedStyle(el);
        if (cs.display === 'none' || cs.visibility === 'hidden') return;
        const r = el.getBoundingClientRect();
        if (r.width <= 0 || r.height <= 0) return;
        maxBottom = Math.max(maxBottom, r.bottom - sr.top);
        maxRight = Math.max(maxRight, r.right - sr.left);
        minTop = Math.min(minTop, r.top - sr.top);
        minLeft = Math.min(minLeft, r.left - sr.left);
      });
      // 充填率: 本文領域のうち、実際に中身が占めている縦方向の割合。
      // 高さの単純合計だと margin:auto や flex の余りを内容として数えてしまうため、
      // 中身のある直下要素の [top, bottom] 区間を求めて重なりを併合し、合計長を使う。
      // 要素の隙間(auto マージンや .grow によるスペース)は区間に含まれないので、
      // どちらの組み方のデッキでも同じ意味の数値になる。
      let used = null, avail = null;
      if (body) {
        const bs = getComputedStyle(body);
        const top0 = body.getBoundingClientRect().top + parseFloat(bs.paddingTop);
        avail = body.clientHeight
              - parseFloat(bs.paddingTop) - parseFloat(bs.paddingBottom);

        // 直下要素だけを見ると、伸縮して枠いっぱいになった行が中身なしでも
        // 満杯として数えられてしまう。実際に描画のある要素(自前のテキスト・
        // 画像・背景・枠線を持つもの)だけを拾う。
        const spans = [];
        for (const el of body.querySelectorAll('*')) {
          const cs = getComputedStyle(el);
          if (cs.display === 'none' || cs.visibility === 'hidden') continue;
          const ownText = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
          const media = /^(IMG|SVG|CANVAS|TABLE|HR)$/.test(el.tagName);
          const bg = !/^rgba\(0, 0, 0, 0\)$|^transparent$/.test(cs.backgroundColor);
          const border = ['Top', 'Bottom', 'Left', 'Right']
              .some(s => parseFloat(cs['border' + s + 'Width']) > 0);
          if (!(ownText || media || bg || border)) continue;
          const r = el.getBoundingClientRect();
          if (r.height <= 0) continue;
          spans.push([r.top - top0, r.bottom - top0]);
        }
        spans.sort((a, b) => a[0] - b[0]);
        used = 0;
        let curS = null, curE = null;
        for (const [s, e] of spans) {
          if (curS === null) { curS = s; curE = e; continue; }
          if (s <= curE) { curE = Math.max(curE, e); }
          else { used += curE - curS; curS = s; curE = e; }
        }
        if (curS !== null) used += curE - curS;
      }
      rows.push({
        page: i + 1,
        w: Math.round(sr.width), h: Math.round(sr.height),
        bottom: Math.round(maxBottom), right: Math.round(maxRight),
        top: Math.round(minTop === 1e9 ? 0 : minTop),
        left: Math.round(minLeft === 1e9 ? 0 : minLeft),
        used: used === null ? null : Math.round(used),
        avail: avail === null ? null : Math.round(avail)
      });
    });
    return rows;
  }
  function emit() {
    let pre = document.getElementById('__probe__');
    if (!pre) { pre = document.createElement('pre'); pre.id = '__probe__'; document.body.appendChild(pre); }
    pre.textContent = JSON.stringify(measure());
  }
  emit();
  document.addEventListener('DOMContentLoaded', emit);
  window.addEventListener('load', emit);
  setTimeout(emit, 300);
  setTimeout(emit, 1500);
})();
"""


def find_chrome():
    for p in CHROME_CANDIDATES:
        if os.path.exists(p):
            return p
    sys.exit("Chrome / Chromium が見つかりません。CHROME_CANDIDATES にパスを追加してください。")


def probe(html_path):
    src = open(html_path, encoding="utf-8").read()
    base = os.path.dirname(os.path.abspath(html_path))
    # 相対パスの画像を絶対パス化(一時ファイルを別の場所に置くため)
    src = re.sub(r'src="(?!https?:|/|data:)', 'src="' + base + "/", src)
    src = src.replace("</body>", "<script>\n" + PROBE_JS + "\n</script>\n</body>")

    tmp = tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8")
    tmp.write(src)
    tmp.close()
    try:
        dom = subprocess.run(
            [find_chrome(), "--headless", "--disable-gpu", "--no-sandbox",
             "--virtual-time-budget=15000", "--dump-dom", "file://" + tmp.name],
            capture_output=True, text=True, timeout=180,
        ).stdout
    finally:
        os.unlink(tmp.name)

    cands = re.findall(r'<pre id="__probe__">(.*?)</pre>', dom, re.S)
    if not cands:
        sys.exit("計測結果を回収できませんでした。HTMLに <section class=\"slide\"> があるか確認してください。")
    return json.loads(html.unescape(max(cands, key=len)))


def report(rows, margin=6):
    """余白 margin[px] 以内まで迫っていたら警告する(印刷時に切れる恐れ)。"""
    print(f"{'page':>4}  {'overflow':>9}  {'fill':>5}  状態")
    ng = 0
    for r in rows:
        over = max(r["bottom"] - r["h"], r["right"] - r["w"], -r["top"], -r["left"])
        fill = None if not r["avail"] else round(r["used"] / r["avail"] * 100)
        flags = []
        if over > 0:
            flags.append("⚠ はみ出し")
            ng += 1
        elif over > -margin:
            flags.append("⚠ 枠ぎりぎり")
        if fill is not None:
            if fill > 100:
                flags.append("⚠ 詰め込みすぎ")
            elif fill < 60:
                flags.append("△ 情報が少ない")
        over_s = f"+{over}px" if over > 0 else "-"
        fill_s = f"{fill}%" if fill is not None else "-"
        print(f"{r['page']:>4}  {over_s:>9}  {fill_s:>5}  {'  '.join(flags) or 'ok'}")

    print()
    fills = [round(r["used"] / r["avail"] * 100) for r in rows if r["avail"]]
    if fills:
        print(f"充填率: 最小 {min(fills)}% / 最大 {max(fills)}% / 平均 {sum(fills) // len(fills)}%")
    print(f"はみ出しページ: {ng} / {len(rows)}")
    return ng


def main():
    ap = argparse.ArgumentParser(description="スライドHTMLのレイアウトを一括検査する")
    ap.add_argument("html", help="スライドHTMLのパス")
    ap.add_argument("--json", action="store_true", help="生の計測結果をJSONで出力")
    args = ap.parse_args()

    rows = probe(args.html)
    if args.json:
        json.dump(rows, sys.stdout, ensure_ascii=False, indent=2)
        print()
        return
    sys.exit(1 if report(rows) else 0)


if __name__ == "__main__":
    main()
