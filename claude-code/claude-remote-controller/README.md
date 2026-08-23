# claude-remote-controller

Claude Code の Remote Control（`claude rc`）をディレクトリ単位で管理する CLI。コマンド名は `claude-rc`。
どのプロジェクトがリモートから触れる状態になっているかを一覧し、その場で ON/OFF と
リストの追加・削除ができる。ログイン時の自動起動も同じバイナリが担当する。

`claude rc` を叩き忘れて、外出先で claude.ai/code やモバイルアプリを開いても
繋ぐ先が無い、という状態を無くすためのツール。

## インストール

```sh
cargo install --git https://github.com/yuto-ts/coding-agent-tools
```

クローンして入れる場合:

```sh
git clone https://github.com/yuto-ts/coding-agent-tools.git
cd coding-agent-tools/claude-code/claude-remote-controller
cargo install --path .
```

どちらも `~/.cargo/bin/claude-rc` が入る（PATH に入っている必要がある）。
更新は同じコマンドに `--force` を付けて実行し直す。
このリポジトリに Rust のパッケージが増えたら、`--git` の後ろに
パッケージ名 `claude-remote-controller` を足して選ぶ。

続けて自動起動を登録する:

```sh
claude-rc setup
```

`setup` は次を行う:

- `~/Library/LaunchAgents/com.<ユーザ名>.claude-rc.plist` を書いて `launchctl bootstrap` する
  （ログイン時と 600 秒ごとに `claude-rc up`）
- `~/.claude/rc-dirs.txt` が無ければ [rc-dirs.example.txt](rc-dirs.example.txt) の内容で作る
  （雛形はバイナリに埋め込んである）

plist には `claude-rc` の絶対パスが入るので、置き場所が変わったら `claude-rc setup` を実行し直す。
自動起動の解除は `claude-rc setup --off`（rc セッションと `~/.claude/rc-dirs.txt` はそのまま残る）。

## 使い方

```
claude-rc              対話画面（一覧 / ON・OFF / 追加・削除）
claude-rc up           登録ディレクトリのうち未起動のものを起動（冪等、launchd 用）
claude-rc list         一覧を表示
claude-rc on  <dir>    起動
claude-rc off <dir>    停止
claude-rc add [dir]    リストに追加（省略時は Finder で選ぶ）
claude-rc rm  <dir>    リストから削除
claude-rc setup        自動起動（LaunchAgent）を登録・更新する
claude-rc setup --off  自動起動を解除する
```

### 対話画面

```
  Claude Remote Control    3/5 起動中

  ▸ ● ~/prog                                  tmux:rc-prog
    ● ~/research/oz-lab                       tmux:rc-oz-lab
    ○ ~/research/phd-admission
    ● ~/prog/internet-deep-girl               外部 pid 17528  (未登録)

  ↑↓ 選択   Space ON/OFF   a Finderで追加   i パス入力で追加   d リストから削除   r 更新   q 終了
```

- `●` は rc が動いている、`○` は止まっている
- 右側は誰が動かしているか。`tmux:...` はこのツールが作ったセッション、
  `外部 pid ...` は別のターミナルで手動起動されたもの
- `(未登録)` は動いているがリストに無いディレクトリ。`i` でパスを打てば登録できる
- `a` は Finder のフォルダ選択ダイアログを開く（その間だけ画面を明け渡す）
- `d` はリストから外すだけで、動いている rc は止めない（止めるのは `Space`）
- 3 秒ごとに状態を取り直すので、別の場所で起動・停止しても追随する

## 設定ファイル

`~/.claude/rc-dirs.txt`。1 行 1 ディレクトリ、`#` 以降はコメント、`~` はホームに展開する。
`add` / `rm` はこのファイルの登録行だけを足し引きし、コメントや並び順はそのまま残す。

```
# 見出しコメント
~/prog
~/research/oz-lab   # 行末コメント
```

## 環境変数

| 変数 | 既定 | 用途 |
|---|---|---|
| `RC_DIRS_FILE` | `~/.claude/rc-dirs.txt` | 対象ディレクトリの一覧 |
| `RC_LOG` | `~/.claude/rc-autostart.log` | `up` のログ |
| `CLAUDE_BIN` / `TMUX_BIN` | PATH と既知の場所から探索 | バイナリのパス |
| `RC_CHECK_INTERVAL` | `600` | `setup` が書く `StartInterval`（秒） |
| `RC_LAUNCH_LABEL` | `com.<ユーザ名>.claude-rc` | LaunchAgent の Label |

## 仕組み

起動は detached な tmux セッション `rc-<ディレクトリ名>` の中で行う。`claude rc` は TUI で
PTY を要求するので、launchd から直接起動すると端末が無くて動かない。副次的に
`tmux attach -t rc-prog` で接続 URL・QR コード・`Capacity: n/32` を後から見られる。

状態の検出は 2 系統ある:

1. `tmux list-sessions` の `rc-` 始まりのセッションとその作業ディレクトリ
2. `pgrep -f 'claude (rc|remote-control)'` で見つけたプロセスの cwd（`lsof`）

同じディレクトリが両方に出たら 1 を優先する。`up` はこの結果を見て、動いていないものだけ
起動するので、手動で起動していた rc を二重に立ち上げることはない。

`up` が何を起動したかは `~/.claude/rc-autostart.log` に残る。launchd 自身の標準出力と
エラーは `~/.claude/rc-autostart.out.log` と `rc-autostart.err.log`。

## 制限

- macOS 専用（launchd、tmux、Finder ダイアログは `osascript` の `choose folder`）
- Remote Control は Claude のサブスクリプション付きアカウントでのログインが必要
- 新しいディレクトリは初回にワークスペース信頼のダイアログが出る。追加したら一度そこで
  `claude` を実行しておく（未承認だと tmux セッションの中でダイアログが出たまま待つ）
- ディレクトリごとに 1 プロセス常駐する（実測で 1 つあたり RSS 80–260 MB）
