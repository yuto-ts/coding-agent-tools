---
description: PR マージ後の後片付け（ワークツリー・ローカル/リモートブランチ・一時ファイルの削除）を安全確認つきで実施する
argument-hint: "[ブランチ名 | PR番号 | ワークツリーのパス]（省略時は現在のブランチ） [--dry-run]"
allowed-tools: Read, Glob, Grep, Bash(pwd), Bash(git status:*), Bash(git branch:*), Bash(git log:*), Bash(git diff:*), Bash(git remote:*), Bash(git worktree list:*), Bash(git rev-parse:*), Bash(git config:*), Bash(git stash list:*), Bash(git fetch:*), Bash(gh pr view:*), Bash(gh pr list:*), Bash(gh repo view:*), Bash(gh auth status:*)
---

# 目的

作業が完了し PR がマージされたあとの後片付けを、**消して良いことを確認してから**明示的に実施する。
「たぶんもう要らない」で消さない。確認 → 計画提示 → 承認 → 実行 の順を必ず守る。

引数: `$ARGUMENTS`

- ブランチ名 / PR 番号 / ワークツリーのパスがあれば、それを対象にする
- 省略時は現在のブランチ（と、そこに紐づくワークツリー）を対象にする
- `--dry-run` があれば **何も削除せず**、実行予定のコマンド一覧だけを提示して終わる

## フェーズ 1: 現状の把握（読み取りのみ）

以下を確認する。git リポジトリでなければその場で伝えて終了する。

1. `pwd` と `git rev-parse --show-toplevel` / `--git-common-dir` — 今いる場所がメインの作業ツリーかワークツリーか
2. `git worktree list` — ワークツリーの一覧と、対象がどれか
3. `git status --porcelain` — 対象ワークツリーの未コミット変更・未追跡ファイル
4. `git stash list` — 対象ブランチに紐づく stash が残っていないか
5. `git log --oneline @{u}.. 2>/dev/null` — 未 push のコミットがないか
6. `git branch -vv` / `git remote -v` — 追跡関係とリモート名
7. PR の状態:
   - `gh pr view <対象> --json number,title,state,mergedAt,mergeCommit,headRefName,url`
   - PR 番号が分からなければ `gh pr list --state all --head <ブランチ名>` で探す
   - `gh` が使えない / 認証されていない場合は、`git log <デフォルトブランチ> --oneline | grep` などでマージ済みか確認し、確証が得られなければ**削除せずユーザーに判断を仰ぐ**

## フェーズ 2: 安全チェック

次のいずれかに該当したら、**削除を実行せず**該当項目を挙げて確認を取る。自分の判断で押し切らない。

- PR が `MERGED` ではない（`OPEN` / `CLOSED` を含む）。CLOSED は「マージされずに閉じられた」＝作業が失われる可能性があるので特に慎重に
- 未コミットの変更・未追跡ファイルがある
- 未 push のコミットがある
- 該当する stash が残っている
- ブランチがデフォルトブランチにマージされていない（`git branch --merged <default>` に出てこない）
- 対象が現在のブランチ / 現在いるワークツリー自身（→ 削除前にメインの作業ツリーへ移動し、デフォルトブランチへ切り替える必要がある）

「消えても困らないゴミなので消す」と判断した未追跡ファイルは、**消す前に一覧を提示**する。

## フェーズ 3: 片付け計画の提示

実行するコマンドを、そのままの形で番号つきで提示する。何がどうなるかを1行ずつ添える。

```
1. git -C <メイン作業ツリー> worktree remove <path>     # ワークツリー削除（中の作業ファイルも消える）
2. git -C <メイン作業ツリー> branch -d <branch>          # ローカルブランチ削除（マージ済みのみ）
3. git push origin --delete <branch>                     # リモートブランチ削除（未削除の場合のみ）
4. git worktree prune && git fetch --prune               # 参照の整理
5. rm <一時ファイル...>                                  # 作業中に作った一時ファイル（あれば個別に列挙）
```

そして**ユーザーの承認を待つ**。`--dry-run` の場合はここで終了する。

## フェーズ 4: 実行

承認後、上から順に実行する。

- 実行は**必ずメインの作業ツリーから**行う（`git -C <toplevel>` を使う）。削除対象のワークツリー内に cd したまま `worktree remove` しない
- ブランチ削除は `-d` を使う。`-D`（強制削除）はマージ済みが確認できない場合に限り、**理由を説明してユーザーの明示的な承認を取ってから**使う
- リモートブランチは、GitHub の "Automatically delete head branches" で既に消えていることが多い。`git ls-remote --heads origin <branch>` で存在を確認してから削除する
- ワークツリーが `git worktree remove` で拒否される（変更が残っている等）場合、`--force` に飛ぶ前に理由を提示して確認する
- このセッションが harness のワークツリー分離下にある場合は、ディレクトリを消す前に `ExitWorktree` で抜ける
- 各コマンドの失敗は握りつぶさず報告し、続行するか確認する

## フェーズ 5: 結果の報告

- 削除したもの / 残したもの（と残した理由）を箇条書きで報告する
- `git worktree list` と `git branch` の結果を最後に確認し、片付いた状態を示す
- 後片付けの対象外だが気づいた残骸（古いワークツリー、マージ済みの他ブランチ、放置された一時ファイル）があれば、**消さずに**「他にもこれが残っています」と列挙して次の判断材料にする

## 守ること

- マージ済みの確証が取れないものは消さない。迷ったら残して報告する
- `rm -rf` を使うなら対象パスを事前に提示して承認を得る。ワイルドカードでまとめて消さない
- ユーザーが「全部消して」と言った場合でも、未コミット変更・未 push コミットの存在は必ず先に伝える（伝えた上で本人が消すと言うなら従う）
