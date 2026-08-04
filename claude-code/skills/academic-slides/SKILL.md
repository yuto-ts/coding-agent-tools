---
name: academic-slides
description: Build presentation slides from a paper, thesis, or research write-up as a self-contained HTML deck that renders to PDF, and optionally to an editable .pptx for Google Slides. Use this whenever the user wants slides for a talk — conference presentation, thesis defense, lab meeting, admission interview, journal club, research summary — or asks to turn a paper or PDF into a deck, draft a slide outline, or prepare presentation materials. Also use it when they want speaker notes to accompany slides, when they ask to restyle or fix layout problems in an existing HTML deck, or when they mention slide constraints like font sizes, citation placement, figure extraction, or information density. Covers planning the slide flow, pulling figures out of the source PDF, enforcing a consistent design system in CSS, and verifying every page fits before shipping.
---

# 学術発表スライドの作成

論文や研究内容から発表スライドを作る。**HTML を正本にして PDF を生成する**方式を取り、必要なら Google Slides で手直しできる `.pptx` も書き出す。

## なぜ HTML を正本にするのか

PowerPoint を直接組むより HTML のほうが向いている理由は3つある。

1. **体裁のルールを CSS で機械的に強制できる。** 「文字サイズは3段階まで」「引用は小さく右下」といった規約は、人手で守ると必ず崩れる。CSS 変数で一元管理すれば破りようがない。
2. **差分が読める。** 文言の推敲は何度も往復する。テキストなので git で追え、レビューもできる。
3. **レイアウトを機械的に検証できる。** 後述するが、これが品質と速度を最も左右する。

生成物(PDF / pptx)は使い捨てで、直すときは必ず HTML 側を直す。この原則を崩すと二重管理になって破綻する。

## ワークフロー

### 1. 出典を読み、構成を決める

まず論文なり原稿なりを通読する。そのうえで**スライドを書く前に構成案を作り、ユーザーに見せて合意を取る**。ここを飛ばすと、作り込んだ後で全面的にやり直しになる。

構成案には各ページについて「見出し」「載せる文言」「使う図」を書く。文言は最終形の文体で書いておくと、後の実装が写経で済む。

**枚数の目安は「本編スライド数 ≒ 発表時間(分)」。** 15分なら本編14枚程度。これを超えるなら内容を削るか、補足スライドに逃がす。

**構成の型**(研究発表の場合):

| ページ | 役割 |
|---|---|
| 1 | タイトル |
| 2 | 研究概要 — 何をしたか・新規性・主な結果を1枚で |
| 3–5 | 背景(既知)→ 課題(未解明)→ 関連研究と本研究の立ち位置 |
| 6–9 | アプローチ → 提案手法 → システム/実装 |
| 10–13 | 実験 → 評価 |
| 14 | まとめ(成果と今後の課題) |
| 補足 | 質疑用。式の詳細、追加データ、失敗例、参考文献一覧 |

2枚目の概要スライドは効果が大きい。聞き手が以降の話を追う地図になる。

### 2. 図版を抽出する

出典が PDF なら `scripts/extract_figures.py` を使う。論文の図は多くが埋め込み画像なので、ページ全体をラスタライズするより **`pdfimages` で埋め込み画像を取り出すほうが遥かに高画質**になる。

```bash
python3 scripts/extract_figures.py paper.pdf --list-pages 3,5,12    # まず何があるか見る
python3 scripts/extract_figures.py paper.pdf --page 5 --index 0 --out assets/deform.png
```

図にキャプション(「Fig. 3. ...」)が焼き込まれている場合は `--crop` で落とす。スライド側で自前のキャプションを付けるほうが、言語も文体も揃う。グラフの余白が広いときは `--trim` で自動的に詰める。

透過を含む図は、スクリプトが透過マスクを白背景に合成する(合成した場合はその旨を表示する)。PDF内で線画として描かれているベクタ図は埋め込み画像として存在しないので、その場合は `--render --dpi 200` でページをレンダリングしてから `--crop` で切り出す。`--list` の結果に目当ての図が出てこなければベクタ図だと判断してよい。

**論文の図をそのまま貼れない場合は自分で作る。** 特に「対比」「分類」「割合」は、論文の表や本文をそのまま載せるより、CSS で図解したほうが伝わる。テンプレートに 2×2 マトリクス・Before/After 対比・横棒グラフの実装例が入っている。

### 3. HTML を書く

`assets/deck.html` をコピーして使う。1280×720px 固定・16:9 で、1 `<section class="slide">` が PDF の1ページに対応する。デザインシステム(色・文字サイズ・部品)は CSS 変数と既存クラスで完結しているので、**新しい色やサイズを足さずに済ませる**のが原則。

体裁の詳細は **`references/design.md`** を読む。文字サイズの段階数、色数、引用の置き方、余白、図解の使い分けの根拠が書いてある。

言語ごとの文体規約は使う言語のファイルだけ読めばよい。

- 日本語で作る → **`references/japanese.md`**(体言止め、括弧、フォント指定)
- 英語で作る → **`references/english.md`**(sentence fragments、フォント指定)

### 4. レイアウトを機械的に検証する ← ここが要

**PDF を画像に変換して1枚ずつ目視で確認してはいけない。** 遅いうえに見落とす。18枚のデッキで画像を読むと何往復もかかり、修正のたびに繰り返すことになる。

代わりに `scripts/check_layout.py` を使う。ヘッドレスブラウザで全ページの全要素の座標を測り、**枠外へのはみ出し**と**情報の充填率**を一覧で返す。

```bash
python3 scripts/check_layout.py deck.html
```

```
page  overflow  fill   状態
   3         -   84%   ok
   8      +63px  100%  ⚠ 下端はみ出し
  12         -   61%   △ 情報が少ない
```

- **overflow が出たページは必ず直す。** PDF では黙って切れるため、放置すると気付かないまま提出することになる。
- **fill が低いページは内容を足すか、図を大きくする。** 目安として本編は 70〜95% に収める。100% を超えるページは詰め込みすぎで、いずれ溢れる。
- fill は「本文領域のうち中身が縦方向に占める割合」で、要素間の空きは含まない。文字を小さくして数値を上げようとしない。先に試すのは主文+補足の2段構成と、図の拡大。

目視は「文字の折り返しが不自然でないか」「図の見え方」など、数値で測れないものに限って、修正が一通り終わってから2〜3枚だけ確認する。

### 5. PDF を生成する

```bash
bash scripts/build_pdf.sh deck.html deck.pdf
```

Chrome のヘッドレス印刷を使う。ページ数と用紙サイズ(960×540pt = 16:9)が出力されるので、想定と一致するか確認する。

### 6. 発表原稿を別ファイルに書く

スライド本体とは別に `script.md` を作る。**読み上げ原稿ではなく「何を話すか」の箇条書き**にする。原稿を書くと棒読みになり、箇条書きなら自分の言葉で話せる。

- スライドに載せなかった数値・定義・条件はすべてここに集約する。スライドが薄くなるのを恐れずに済む
- 各ページの目安時間を書き、合計が持ち時間に収まることを確認する
- 想定質疑と回答方針も入れておく。補足スライドとの対応表があると本番で探せる

### 7. (任意)Google Slides 用に pptx を書き出す

ユーザーが「Google Slides で手直ししたい」「共同編集したい」と言った場合のみ実行する。既定は PDF だけでよい。

```bash
bash scripts/export_pptx.sh deck.html deck.pptx
```

レイアウトを手作業で組み直すのではなく、**ブラウザが計算した実座標を抽出して python-pptx でテキストボックス化する**。HTML を直して再実行すれば pptx も追随するので、二重管理にならない。

取り込みは「Google ドライブにアップロード → 右クリック → アプリで開く → Google スライド」。

事前に伝えるべき制約が3つある。

- **フォント置換で行の折り返しが数文字ずれる。** Noto Sans JP を指定しているが、元の字幅とは異なる
- **破線は実線になる。** 必要なら Slides 上で戻す
- **1行が1テキストボックス**になるため、段落をまたぐ一括編集はできない。大きな変更は HTML 側で行うほうが速い

`python-pptx` が未導入なら `pip3 install python-pptx` が必要。

## 品質のチェックリスト

提出前に確認する。

- [ ] 全ページで overflow なし(`check_layout.py`)
- [ ] 本編の充填率が 70〜95%
- [ ] 文字サイズが規定の段階数に収まっている
- [ ] 背景・課題・関連研究に引用がある。番号はスライド登場順
- [ ] 全ページにページ番号(質疑でページを指定してもらうため)
- [ ] 1スライド1メッセージ。見出しがそのページの主張になっている
- [ ] 対比・分類の内容が箇条書きのままになっていないか(図解に置き換える)
- [ ] script.md の合計時間が持ち時間に収まっている

## 同梱物

```
scripts/
  extract_figures.py   出典PDFからの図版抽出(埋め込み画像取り出し・キャプション除去・余白トリム)
  check_layout.py      全ページのはみ出しと充填率を一括検査 ← 毎回使う
  build_pdf.sh         Chrome headless で PDF 化
  export_pptx.sh       pptx 書き出し(下の2つを呼ぶ)
  layout_dump.js         ブラウザ上でレイアウトを JSON 化
  export_pptx.py         JSON から pptx を組み立て
assets/
  deck.html            デッキのテンプレート(CSS デザインシステム + 部品の実装例)
references/
  design.md            体裁の原則と根拠。HTML を書く前に読む
  japanese.md          日本語スライドの文体規約
  english.md           英語スライドの文体規約
```

スクリプトはスキルのディレクトリから作業ディレクトリにコピーせず、パスを指定して直接実行してよい。`deck.html` だけは作業ディレクトリにコピーして編集する。
