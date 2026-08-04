#!/usr/bin/env python3
"""論文PDFから図版を取り出す。

論文の図は多くが埋め込み画像なので、ページをラスタライズするより
pdfimages で埋め込み画像そのものを取り出すほうが高画質になる。

  # まず何ページ目に何が入っているか調べる
  python3 extract_figures.py paper.pdf --list 3,5,12

  # 5ページ目の0番目の画像を取り出す
  python3 extract_figures.py paper.pdf --page 5 --index 0 --out assets/fig2.png

  # 図の下に焼き込まれたキャプションを落とす / 余白を詰める / 幅を揃える
  python3 extract_figures.py paper.pdf --page 5 --index 0 --out assets/fig2.png \
      --crop 0,0,542,255 --trim --max-width 900

  # 埋め込み画像がない(ベクタ図)ときはページをレンダリングして切り出す
  python3 extract_figures.py paper.pdf --page 7 --render --dpi 200 --out work/p7.png

依存: poppler (pdfimages / pdftoppm), Pillow
"""
import argparse
import glob
import os
import subprocess
import sys
import tempfile

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow が必要です: pip3 install Pillow")


def run(cmd):
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"コマンドが失敗しました: {' '.join(cmd)}\n{r.stderr}")
    return r.stdout


def list_pages(pdf, pages):
    for p in pages:
        print(f"=== page {p} ===")
        print(run(["pdfimages", "-list", "-f", str(p), "-l", str(p), pdf]))
        print("  ※ smask 行はマスクなので index には数えない。"
              "index は image 行を上から 0,1,2... と数える")


def autocrop(im, margin=6, thresh=248):
    """白背景の余白を落とす。グラフの周囲が広く空いているときに使う。"""
    gray = im.convert("L").point(lambda v: 0 if v >= thresh else 255)
    bbox = gray.getbbox()
    if not bbox:
        return im
    l, t, r, b = bbox
    return im.crop((max(l - margin, 0), max(t - margin, 0),
                    min(r + margin, im.width), min(b + margin, im.height)))


def parse_list(pdf, page):
    """pdfimages -list を解析して (num, type, object_id) の並びを返す。

    smask 行は直前の image 行と同じ object id を持つ。この対応が取れないと
    透過画像を単体で取り出すことになり、透過部分が黒く潰れる。
    """
    rows = []
    for line in run(["pdfimages", "-list", "-f", str(page), "-l", str(page), pdf]).splitlines():
        f = line.split()
        # page num type width height color comp bpc enc interp object_id ...
        if len(f) < 11 or not f[0].isdigit():
            continue
        try:
            rows.append({"num": int(f[1]), "type": f[2], "obj": f[10]})
        except (ValueError, IndexError):
            continue
    return rows


def load_with_alpha(prefix, rows, index):
    """index 番目の実画像を、対応する smask があれば白背景に合成して返す。"""
    images = [r for r in rows if r["type"] == "image"]
    if not images:
        sys.exit("埋め込み画像がありません。--render を試してください")
    if index >= len(images):
        sys.exit(f"index {index} は範囲外です(このページの画像は {len(images)} 個)")
    target = images[index]

    def path_for(num):
        # pdfimages は prefix-000.png のように num をゼロ詰めしたファイル名で出す
        for w in (3, 4, 2):
            p = f"{prefix}-{num:0{w}d}.png"
            if os.path.exists(p):
                return p
        return None

    src = path_for(target["num"])
    if not src:
        sys.exit("画像ファイルの取り出しに失敗しました")
    im = Image.open(src).convert("RGB")

    smask = next((r for r in rows if r["type"] == "smask" and r["obj"] == target["obj"]), None)
    if smask:
        mp = path_for(smask["num"])
        if mp:
            alpha = Image.open(mp).convert("L").resize(im.size, Image.LANCZOS)
            bg = Image.new("RGB", im.size, (255, 255, 255))
            im = Image.composite(im, bg, alpha)
            print("  透過マスクを白背景に合成しました")
    return im


def extract(pdf, page, index, out, crop, trim, max_width, render, dpi):
    tmp = tempfile.mkdtemp()
    prefix = os.path.join(tmp, "x")
    if render:
        run(["pdftoppm", "-r", str(dpi), "-png", "-f", str(page), "-l", str(page), pdf, prefix])
        files = sorted(glob.glob(prefix + "*.png"))
        if not files:
            sys.exit("ページのレンダリングに失敗しました")
        im = Image.open(files[0]).convert("RGB")
    else:
        rows = parse_list(pdf, page)
        run(["pdfimages", "-png", "-f", str(page), "-l", str(page), pdf, prefix])
        im = load_with_alpha(prefix, rows, index)

    print(f"  元サイズ: {im.size}")
    if crop:
        im = im.crop(tuple(int(v) for v in crop.split(",")))
    if trim:
        im = autocrop(im)
    if max_width and im.width > max_width:
        im = im.resize((max_width, int(im.height * max_width / im.width)), Image.LANCZOS)

    os.makedirs(os.path.dirname(os.path.abspath(out)) or ".", exist_ok=True)
    im.save(out)
    print(f"  保存: {out} {im.size}")


def main():
    ap = argparse.ArgumentParser(description="論文PDFから図版を取り出す")
    ap.add_argument("pdf")
    ap.add_argument("--list", help="指定ページの埋め込み画像を一覧する(例: 3,5,12)")
    ap.add_argument("--page", type=int, help="対象ページ(1始まり)")
    ap.add_argument("--index", type=int, default=0, help="そのページの何番目の画像か")
    ap.add_argument("--out", help="出力先のパス")
    ap.add_argument("--crop", help="切り出し範囲 left,top,right,bottom(キャプション除去に使う)")
    ap.add_argument("--trim", action="store_true", help="白背景の余白を自動で詰める")
    ap.add_argument("--max-width", type=int, help="この幅を超える場合は縮小する")
    ap.add_argument("--render", action="store_true", help="埋め込み画像ではなくページ全体をレンダリング")
    ap.add_argument("--dpi", type=int, default=200, help="--render 時の解像度")
    args = ap.parse_args()

    if args.list:
        list_pages(args.pdf, [int(p) for p in args.list.split(",")])
        return
    if not (args.page and args.out):
        ap.error("--page と --out が必要です(または --list)")
    extract(args.pdf, args.page, args.index, args.out,
            args.crop, args.trim, args.max_width, args.render, args.dpi)


if __name__ == "__main__":
    main()
