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
  アクセストークンは失効の 60 分前からリフレッシュを試み始め、成功するまで
  tick(5分)ごとに再試行する。token エンドポイントは 429 (rate_limit_error)
  を返しやすく(約4時間に1回、anthropics/claude-code#38248)、かつ `claude`
  CLI 自身のリフレッシュと予算を共有しているため、429 を受けたら 30 分は
  リトライしない(`~/.runcat/.claude-refresh-fail`)。60分の試行ウィンドウが
  あるので、この間隔でも期限内にどこかで成功しやすい。リフレッシュに失敗
  している間も、旧アクセストークンがまだ有効ならそれを使い続ける。
  新トークン取得に成功すると Claude Code と同じ形式で Keychain に書き戻す。

  トークンが完全に失効し直接取得もできない場合は、statusline が書く
  `/tmp/claude-usage-cache.json` にフォールバックする。この場合
  `lastUpdatedDate` にはキャッシュの mtime を入れ、メニューバーに
  `C 27%~`(チルダ付き)、ダッシュボードに `⏳ stale / 2.7h 前のキャッシュ`
  の行を追加して、古い値を現在値のように見せないようにする。

  **リフレッシュトークン自体が無効(`invalid_grant`)になった場合のみ、真の
  再ログインが必要。** その場合は 6 時間リトライを止め、下記の通知を行う。
  復旧はターミナルで `claude`(→ `/login`)を実行して再認証し、Keychain の
  トークンを作り直すのが確実。再認証後は launchd の次回実行(5分以内)で
  自動的に最新値に更新される。

### 認証切れの検知

`claude login` はブラウザで本人が承認する OAuth フローなので、launchd の
バックグラウンドジョブから自動ログインを完結させることはできない。
代わりに `invalid_grant`(リフレッシュトークンが本当に無効)を検知したときだけ
以下を行う。429 によるレート制限では通知しない:

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
- リフレッシュのバックオフ理由確認: `cat ~/.runcat/.claude-refresh-fail`
  (`rate_limited` = 一時的、自動で復旧 / `invalid_grant` = 要 `/login`)
