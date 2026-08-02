# RunCat Neo custom metrics: Claude / Codex rate limits

[RunCat Neo のカスタムメトリクス](https://zenn.dev/kyome/articles/eb4a9f664002ad) 用に、
Claude Code と Codex (ChatGPT) のレート制限使用率を JSON で書き出すスクリプト。

## 出力

5 分毎に launchd が [update-metrics.sh](update-metrics.sh) を実行し、以下を上書きする
(RunCat Neo はファイル監視型なので、書き換われば自動で表示が更新される):

- `~/.runcat/claude-usage.json` — 5h / Weekly の使用率とリセット時刻
- `~/.runcat/codex-usage.json` — 同上

## データソース

- **Claude**: Keychain `Claude Code-credentials` の OAuth トークンで
  `https://api.anthropic.com/api/oauth/usage` を叩く。
  アクセストークンが期限切れの場合は refresh token で更新し、
  新トークンを Claude Code と同じ形式で Keychain に書き戻す。
  ただし token エンドポイントは 429 (rate_limit_error) を返しやすく
  (約4時間に1回、anthropics/claude-code#38248)、短間隔でリトライすると
  制限を張りっぱなしにして `claude` CLI 自身のリフレッシュまで失敗させてしまう。
  そのため失敗後 6 時間はリフレッシュを試みない(`~/.runcat/.claude-refresh-fail`)。
  その間は statusline が書く `/tmp/claude-usage-cache.json` にフォールバックし、
  `lastUpdatedDate` にはキャッシュの mtime を入れる(古さが分かるように)。

  **トークンが失効しリフレッシュも 429 で通らない場合、直接取得もキャッシュも
  更新できず値が固定される。復旧はターミナルで `claude`(→ `/login`)を実行して
  再認証し、Keychain のトークンを作り直すのが確実。** 再認証後は launchd の
  次回実行(5分以内)で自動的に最新値に更新される。

### 認証切れの検知

`claude login` はブラウザで本人が承認する OAuth フローなので、launchd の
バックグラウンドジョブから自動ログインを完結させることはできない。
代わりに認証切れを検知して以下を行う:

1. macOS 通知を出す(6時間に1回にスロットル、`~/.runcat/.claude-auth-notified`)
2. RunCat 上でも分かるように、メニューバー表示を `C ⚠️` にし、
   `⚠️ 認証切れ / claude /login が必要` の行を追加する
   (古いキャッシュ値を現在値のように見せない)

再認証に成功すると通知スタンプは自動で消え、通常表示に戻る。

`RUNCAT_AUTO_LOGIN=1` を設定すると、通知に加えて Terminal を開いて
`claude login` を実行する(承認自体はブラウザで本人が行う必要がある)。
既定は無効 — 5分毎のジョブが勝手にウィンドウを開くのを避けるため。
- **Codex**: `~/.codex/sessions/**/*.jsonl` の最新 `token_count` イベントの
  `rate_limits` を読む(ネットワーク不要)。Codex を使った時点の値なので、
  しばらく使っていないと古い値のままになる。

## セットアップ

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.yuto-ts.runcat-metrics.plist
```

RunCat Neo 側: 設定 > メトリクス > カスタムメトリクス から
`~/.runcat/claude-usage.json` と `~/.runcat/codex-usage.json` を登録する。

## 運用

- ログ: `~/.runcat/update-metrics.log`
- 停止: `launchctl bootout gui/$(id -u)/com.yuto-ts.runcat-metrics`
- 手動実行: `bash update-metrics.sh`
- API エラー時は前回の JSON を残す(`lastUpdatedDate` が古いままになる)
