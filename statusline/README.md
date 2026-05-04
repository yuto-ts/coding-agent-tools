# statusline

Claude Code の statusLine 用シェルスクリプトです。以下を 1 行〜複数行で表示します。

- モデル表示名 / コンテキスト使用率 / Git ブランチ / `◑thinking`
- **current**: 5 時間ウィンドウのレートリミット消費率（ドットバー + リセット時刻）
- **weekly**: 7 日ウィンドウのレートリミット消費率
- **extra**: 追加クレジットの使用額 / 上限額（有効な場合のみ）

レートリミット情報は `https://api.anthropic.com/api/oauth/usage`（Claude Code の `/usage` が裏で叩いているのと同じエンドポイント）から取得し、`/tmp/claude-usage-cache.json` にキャッシュします。

## 必要環境

- macOS（`security` コマンドでキーチェーンからトークン取得、`date -j` の macOS 固有フラグを使用）
- `bash`, `jq`, `curl`
- Claude Code でログイン済みであること（`Claude Code-credentials` という名前でキーチェーンに OAuth トークンが保存されている前提）

## インストール

```sh
./install.sh
```

これで `~/.claude/statusline-command.sh` が本リポジトリのスクリプトへのシンボリックリンクになります。既存ファイルがある場合は `*.bak` に退避します。

その後、`~/.claude/settings.json` に以下を追記してください（既にある場合は不要）。

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

## キャッシュとレートリミット

`/api/oauth/usage` は Anthropic の OAuth 専用エンドポイントで、独自のレートリミットがあります（公式に値の記載は無し、429 が永続化する報告あり: [claude-code#31021](https://github.com/anthropics/claude-code/issues/31021), [#31637](https://github.com/anthropics/claude-code/issues/31637)）。本スクリプトでは:

- 成功レスポンスは `/tmp/claude-usage-cache.json` に **5 分** キャッシュ（`CACHE_TTL=300`）
- レートリミット等のエラー応答はキャッシュに焼き付けず、`/tmp/claude-usage-cache.error` をマーカーに **5 分** バックオフ（`ERROR_BACKOFF=300`）
- 強制再試行したい場合: `rm -f /tmp/claude-usage-cache.error`

## API 呼び出しの注意点

実装上の落とし穴を 2 つ記録しておきます（公式ドキュメント未記載）。

1. **`anthropic-beta: oauth-2025-04-20` ヘッダが必須**。これが無いと `OAuth authentication is currently not supported` (HTTP 401) が返る
2. レスポンスの `utilization` は **0–100 の値** で返る（0–1 の小数ではない）

## カスタマイズ

スクリプト冒頭の以下の値を直接編集してください。

- `TZ="Asia/Tokyo"` ハードコード箇所（リセット時刻表示のタイムゾーン） — 他地域で使うなら書き換え
- `CACHE_TTL` / `ERROR_BACKOFF` — 取得頻度
- 配色（先頭の `CYAN` `ORANGE` `GREEN` `RED` `GRAY` `WHITE`）

## 表示例

```
Opus 4.7 │ ✏️ 12% │ main │ ◑thinking
current ●●●●○○○○○○ 45% ↺4:20am
weekly  ●○○○○○○○○○ 17% ↺May 5, 8:00am
extra   ○○○○○○○○○○ $0.00/$2000.00
```
