---
description: マージ済みブランチの worktree・ブランチ・プレビューを後片付けする
argument-hint: "[issue番号 / ブランチ名 / worktree のパス](省略時は今いる worktree)"
allowed-tools: Bash(git *), Bash(gh pr *), Bash(ls *)
---

1 issue = 1 worktree で作業したあとの後片付けをする。

## 対象を決める

`$ARGUMENTS` があればそれを対象にする。

- **issue 番号** — `git worktree list` と `git branch` から、その番号を含むブランチ/worktree を探す。
  複数見つかったら候補を出して聞く
- **ブランチ名 / worktree のパス** — そのまま使う

`$ARGUMENTS` が無ければ、**今いる worktree のブランチ**が対象。

**原本(main worktree)のパスは `git worktree list` の1行目**から取る。決め打ちしない。
以降のコマンドはすべて `git -C <原本>` で実行する(理由は下の注意)。

## 消す前に確認する

**次の3つを確認してから削除に進む。**未マージの作業やコミットしていない変更を消さないため。

1. **マージ済みか。** `gh pr list --head <ブランチ> --state merged --json number,mergedAt`
   (PR 番号が分かっていれば `gh pr view <番号> --json state,mergedAt`)。
   **マージされていなければここで止めて報告する。**勝手に消さない。
   `gh` が無い/リモートが無いリポジトリなら `git branch --merged main` で代用する
2. **未コミットの変更が無いか。** `git -C <worktree> status --porcelain -uall` が空であること。
   何か残っていれば内容を見せて、どうするか聞いてから進む
3. **その worktree 用に起動したものが残っていないか。** dev サーバやプレビューを立てていれば止める。
   ポートや DB を worktree ごとに分けて並列作業する運用なら、次のセッションのために必ず解放する

## 片付ける

4. `git -C <原本> worktree remove <worktree のパス>`
5. `git -C <原本> branch -d <ブランチ>`
6. `git -C <原本> push origin --delete <ブランチ>`(リモートに残っていれば)
7. `git -C <原本> checkout main && git -C <原本> pull --ff-only`
8. `git -C <原本> worktree list` で消えたことを確認して報告する

## 注意

- **必ず `git -C <原本>` を使う。** worktree の中に cd した状態でその worktree を消すと、
  シェルの cwd が消えて後続のコマンドが全部こける
- `branch -d` の「origin にはマージ済みだが HEAD にはまだ」という警告は、
  手順1でマージを確認済みなら無視してよい
- **今回の片付けと関係ない未コミットの変更には手を出さない。**見つけたら報告だけする
- **他の worktree には触らない。**並列で別の作業が走っている可能性がある
