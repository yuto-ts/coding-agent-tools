/* slides.html の実レイアウト(ブラウザ計算結果)を JSON として書き出す。
   Chrome --headless --dump-dom で末尾の pre 要素を回収する(export_pptx.sh)。 */
(function () {
  const INLINE = new Set(['SPAN', 'B', 'STRONG', 'I', 'EM', 'SUB', 'SUP', 'A', 'BR', 'SMALL', 'CODE']);

  function rgb(str) {
    const m = String(str).match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const p = m[1].split(',').map(parseFloat);
    if (p.length >= 4 && p[3] < 0.05) return null;
    return [Math.round(p[0]), Math.round(p[1]), Math.round(p[2])];
  }
  /* タグ名ではなく実際の display で判定する。
     span でも CSS で display:block なら独立したテキストとして扱う(二重出力の防止) */
  function isInlineNode(n) {
    if (n.nodeType !== 1) return false;
    if (n.tagName === 'BR') return true;
    if (!INLINE.has(n.tagName)) return false;
    return getComputedStyle(n).display.indexOf('inline') === 0;
  }
  const isTextNode = (n) => n.nodeType === 3 && n.textContent.trim() !== '';

  function run() {
    const out = [];
    document.querySelectorAll('section.slide').forEach((slide, idx) => {
      const sr = slide.getBoundingClientRect();
      const shapes = [];
      const rel = (r) => ({
        x: +(r.left - sr.left).toFixed(1), y: +(r.top - sr.top).toFixed(1),
        w: +r.width.toFixed(1), h: +r.height.toFixed(1)
      });

      function styleOf(el, pseudo) {
        const cs = getComputedStyle(el, pseudo || null);
        const fs = parseFloat(cs.fontSize);
        return {
          size: fs,
          bold: parseInt(cs.fontWeight, 10) >= 600,
          italic: cs.fontStyle === 'italic',
          color: rgb(cs.color) || [0, 0, 0],
          align: cs.textAlign,
          lh: cs.lineHeight === 'normal' ? 1.25 : parseFloat(cs.lineHeight) / fs,
          serif: /times|serif/i.test(cs.fontFamily)
        };
      }

      function runsFrom(nodes, base) {
        const acc = [];
        const visit = (node, st) => {
          if (node.nodeType === 3) {
            // ASCII 空白のみ畳む。全角スペース(U+3000)は意図的な字間なので残す
            const t = node.textContent.replace(/[ \t\n\r\f\v]+/g, ' ');
            if (t.replace(/[ \t\n\r\f\v]/g, '') !== '') acc.push(Object.assign({}, st, { t }));
            return;
          }
          if (node.nodeType !== 1) return;
          if (node.tagName === 'BR') { acc.push({ br: true }); return; }
          const s2 = styleOf(node);
          const st2 = Object.assign({}, st, {
            size: s2.size, bold: s2.bold, italic: s2.italic, color: s2.color, serif: s2.serif,
            sub: st.sub || node.tagName === 'SUB', sup: st.sup || node.tagName === 'SUP'
          });
          for (const c of node.childNodes) visit(c, st2);
        };
        for (const n of nodes) visit(n, base);
        return acc;
      }

      /* 要素が直接持つテキスト(text node と inline 要素)を、
         block 子要素で分断された「かたまり」ごとに区切って返す */
      function textGroups(el) {
        const groups = [];
        let cur = [];
        for (const n of el.childNodes) {
          // 空白のみのテキストノードもインライン列の一部として保持する(全角スペース対策)
          if (n.nodeType === 3 || isInlineNode(n)) { cur.push(n); }
          else if (n.nodeType === 1) { if (cur.length) groups.push(cur); cur = []; }
        }
        if (cur.length) groups.push(cur);
        return groups.filter(g => g.some(n => isTextNode(n) || (n.nodeType === 1 && n.textContent.trim())));
      }

      function walk(el, isRoot) {
        const cs = getComputedStyle(el);
        if (cs.display === 'none' || cs.visibility === 'hidden') return;
        const r = el.getBoundingClientRect();
        if (r.width <= 0 || r.height <= 0) return;
        const b = rel(r);

        if (!isRoot) {
          const bg = rgb(cs.backgroundColor);
          const sides = ['Top', 'Right', 'Bottom', 'Left'];
          const bw = sides.map(s => parseFloat(cs['border' + s + 'Width']) || 0);
          const bc = sides.map(s => rgb(cs['border' + s + 'Color']));
          const uniform = bw[0] > 0 && bw.every(v => Math.abs(v - bw[0]) < 0.01);
          const radius = parseFloat(cs.borderTopLeftRadius) || 0;
          if (bg || uniform) {
            shapes.push({ k: 'rect', ...b, fill: bg, line: uniform ? { c: bc[0], w: bw[0] } : null, radius });
          }
          if (!uniform) {
            const boxes = [
              { i: 0, x: b.x, y: b.y, w: b.w, h: bw[0] },
              { i: 1, x: b.x + b.w - bw[1], y: b.y, w: bw[1], h: b.h },
              { i: 2, x: b.x, y: b.y + b.h - bw[2], w: b.w, h: bw[2] },
              { i: 3, x: b.x, y: b.y, w: bw[3], h: b.h }
            ];
            for (const s of boxes) {
              if (bw[s.i] > 0) shapes.push({ k: 'rect', x: s.x, y: s.y, w: s.w, h: s.h, fill: bc[s.i], line: null, radius: 0 });
            }
          }
        }

        if (el.tagName === 'IMG') {
          shapes.push({ k: 'img', ...b, src: el.getAttribute('src') });
          return;
        }

        const st = styleOf(el);
        const padL = parseFloat(cs.paddingLeft) + parseFloat(cs.borderLeftWidth);
        const padR = parseFloat(cs.paddingRight) + parseFloat(cs.borderRightWidth);
        // インライン要素のテキストは親がまとめて出力済みなので、ここでは出さない
        const inlineSelf = cs.display.indexOf('inline') === 0;
        // 負の text-indent(箇条書きのぶら下げ)は pptx 側のインデントで再現する
        const ti = parseFloat(cs.textIndent) || 0;
        const hang = ti < 0;
        for (const g of (inlineSelf ? [] : textGroups(el))) {
          const rng = document.createRange();
          rng.setStartBefore(g[0]);
          rng.setEndAfter(g[g.length - 1]);
          const gr = rng.getBoundingClientRect();
          if (gr.height <= 0) continue;
          const base = { size: st.size, bold: st.bold, italic: st.italic, color: st.color, serif: st.serif };
          const rs = [];
          if (el.tagName === 'LI') {
            const bef = getComputedStyle(el, '::before');
            const c = (bef.content || '').replace(/^["']|["']$/g, '');
            if (c && c !== 'none' && c !== 'normal') {
              rs.push({ t: c + ' ', size: parseFloat(bef.fontSize), bold: false, italic: false,
                        color: rgb(bef.color) || st.color });
            }
          }
          rs.push(...runsFrom(g, base));
          if (!rs.length) continue;
          const shp = {
            k: 'text',
            x: +(r.left - sr.left + (hang ? 0 : padL)).toFixed(1),
            y: +(gr.top - sr.top).toFixed(1),
            w: +(r.width - (hang ? padR : padL + padR)).toFixed(1),
            h: +gr.height.toFixed(1),
            align: st.align, lh: st.lh, runs: rs
          };
          if (hang) { shp.marL = +padL.toFixed(1); shp.indent = +ti.toFixed(1); }
          shapes.push(shp);
        }

        for (const c of el.children) walk(c, false);
      }

      walk(slide, true);
      out.push({ page: idx + 1, shapes });
    });
    return out;
  }

  function emit() {
    let pre = document.getElementById('layout-json');
    if (!pre) {
      pre = document.createElement('pre');
      pre.id = 'layout-json';
      document.body.appendChild(pre);
    }
    pre.textContent = JSON.stringify(run());
    document.title = 'layout:' + pre.textContent.length;
  }

  // 画像の読み込み完了後が本命だが、取りこぼしを防ぐため複数回発火させる
  emit();
  document.addEventListener('DOMContentLoaded', emit);
  window.addEventListener('load', emit);
  setTimeout(emit, 300);
  setTimeout(emit, 1500);
})();
