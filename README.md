# claude-code-tools

[Claude Code](https://docs.claude.com/en/docs/claude-code) を快適に使うための自作ツール置き場です。
PC を移行しても再利用しやすいよう、ツールごとに独立したディレクトリ構成にしています。

## ツール一覧

| ディレクトリ | 概要 |
|---|---|
| [`statusline/`](./statusline) | モデル名・コンテキスト使用率・5h / 7d レートリミット消費率を表示する statusline スクリプト |

## 方針

- 各ツールは自身のディレクトリ配下で完結させる（README + 必要なら `install.sh`）
- 個人固有の設定値はリポジトリに含めない（環境変数・引数化する）
- macOS / zsh を主ターゲット（他環境で動かすときはツール側 README を参照）
