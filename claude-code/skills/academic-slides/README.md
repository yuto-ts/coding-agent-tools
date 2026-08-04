# academic-slides

論文や研究内容から学術発表スライドを作る Claude Code スキル。**HTML を正本にして
PDF を生成**し、必要なら Google Slides で手直しできる `.pptx` も書き出す。

学会発表・修士論文発表・入試での研究説明・輪読会などを想定している。日本語と
英語のどちらでも使え、言語ごとの文体規約は `references/` に分けてある。

## なぜ HTML を正本にするのか

PowerPoint を直接組むより、次の3点で有利になる。

- **体裁のルールを CSS で機械的に強制できる。** 「文字サイズは3段階まで」「引用は
  小さく右下」といった規約は人手では必ず崩れる。CSS 変数で一元管理すれば破れない。
- **差分が読める。** 文言の推敲は何度も往復するので、git で追えることが効く。
- **レイアウトを機械的に検証できる。** 下記の `check_layout.py` が全ページの
  はみ出しと情報の充填率を一括で測る。PDF を画像化して目視で確認するより速く、
  かつ見落としがない。

生成物(PDF / pptx)は使い捨てで、直すときは必ず HTML 側を直す。

## 中身

```
SKILL.md                     ワークフロー(構成案 → 図版抽出 → HTML → 検証 → PDF → 原稿)
references/design.md         体裁の原則と根拠(3サイズ・3色・引用の置き方・図解の使い分け)
references/japanese.md       日本語の文体規約(体言止め、括弧、フォント)
references/english.md        英語の文体規約(sentence fragments、フォント)
assets/deck.html             デザインシステム込みのテンプレート。図解6種の実装例つき
scripts/check_layout.py      全ページのはみ出しと充填率を一括検査
scripts/extract_figures.py   論文PDFからの図版抽出(透過合成・キャプション除去・余白トリム)
scripts/build_pdf.sh         Chrome headless で PDF 化
scripts/export_pptx.sh       pptx 書き出し(layout_dump.js + export_pptx.py を呼ぶ)
```

## Install

```sh
./install.sh                       # user-level: ~/.claude/skills/
./install.sh /path/to/repo         # project-level: <repo>/.claude/skills/
```

シンボリックリンクを張るだけなので、このリポジトリを更新すればスキルにも即座に反映される。

## 使い方

論文PDFを渡して「これで15分の発表スライドを作って」と言えば起動する。明示的に呼ぶ場合は
`/academic-slides`。

個々のスクリプトは単体でも使える。

```sh
# 出典PDFの5ページ目にある1つ目の図を取り出す(透過は白背景に合成される)
python3 scripts/extract_figures.py paper.pdf --list 5
python3 scripts/extract_figures.py paper.pdf --page 5 --index 0 --out assets/fig2.png --trim

# 全ページのはみ出しと充填率を検査(はみ出しがあれば終了コード1)
python3 scripts/check_layout.py deck.html

# PDF / pptx を生成
bash scripts/build_pdf.sh   deck.html deck.pdf
bash scripts/export_pptx.sh deck.html deck.pptx
```

`check_layout.py` の出力例。

```
page  overflow  fill   状態
   3         -   84%   ok
   8      +63px 100%   ⚠ はみ出し
  12         -   61%   △ 情報が少ない
```

- **overflow** はスライド枠外にはみ出した量。PDF では黙って切れるため、出たら必ず直す
- **fill** は本文領域のうち中身が縦方向に占める割合。本編は 70〜95% が目安

## 依存

- **Google Chrome または Chromium** — PDF 化とレイアウト計測に使う
- **poppler** (`pdfimages` / `pdftoppm` / `pdfinfo`) — 図版抽出と PDF の確認
- **Pillow** — 図版のクロップと合成
- **python-pptx** — pptx 書き出しのときのみ

```sh
brew install poppler
pip3 install Pillow python-pptx
```

## Google Slides に持ち込む場合

`export_pptx.sh` はレイアウトを手作業で組み直すのではなく、ブラウザが計算した実座標を
抽出して python-pptx でテキストボックス化する。HTML を直して再実行すれば pptx も追随する。

Google ドライブにアップロードし、右クリック →「アプリで開く」→「Google スライド」で
変換される。既知の制約は3つ。

- フォント置換(Noto Sans JP)により行の折り返しが数文字ずれる
- 破線は実線になる
- 1行が1テキストボックスになるため、段落をまたぐ一括編集はできない

大きな変更は HTML 側で行って書き出し直すほうが速い。
