# statusline

A Claude Code `statusLine` script that displays:

- Model display name, context usage %, current Git branch, and a `◑thinking` marker
- **current** — 5-hour rate-limit utilization (dot bar + reset time)
- **weekly** — 7-day rate-limit utilization
- **extra** — additional credit usage / monthly limit (when enabled)

Rate-limit data is fetched from `https://api.anthropic.com/api/oauth/usage`
(the same endpoint Claude Code's `/usage` command uses internally) and cached
in `/tmp/claude-usage-cache.json`.

## Requirements

- macOS — uses the `security` keychain command and macOS-specific `date -j` flags
- `bash`, `jq`, `curl`
- Logged in to Claude Code (the OAuth token is read from the
  `Claude Code-credentials` keychain entry)

## Install

```sh
./install.sh
```

This symlinks `~/.claude/statusline-command.sh` to the script in this repo.
Any existing file at the target is moved aside as `*.bak.<timestamp>`.

Then make sure `~/.claude/settings.json` contains:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  }
}
```

## Caching and rate limits

`/api/oauth/usage` is an OAuth-only endpoint with its own (undocumented) rate
limit. Persistent 429s have been reported even at low polling rates
([claude-code#31021](https://github.com/anthropics/claude-code/issues/31021),
[#31637](https://github.com/anthropics/claude-code/issues/31637)). To stay
well-behaved this script:

- Caches successful responses for **5 minutes** (`CACHE_TTL=300`).
- Never overwrites the cache with an error response. Instead it touches
  `/tmp/claude-usage-cache.error` and backs off for **5 minutes**
  (`ERROR_BACKOFF=300`) before trying again.
- To force an immediate retry: `rm -f /tmp/claude-usage-cache.error`.

## API gotchas

Two things that are not in the public docs and cost time to figure out:

1. The endpoint requires the `anthropic-beta: oauth-2025-04-20` header.
   Without it the response is HTTP 401
   `OAuth authentication is currently not supported`.
2. The `utilization` fields are returned as **0–100** values, not 0–1
   fractions.

## Customization

Edit the constants at the top of `statusline-command.sh`:

- `TZ="Asia/Tokyo"` — timezone used to render reset times. Change for other regions.
- `CACHE_TTL` / `ERROR_BACKOFF` — refresh and back-off intervals (seconds).
- `CYAN` / `ORANGE` / `GREEN` / `RED` / `GRAY` / `WHITE` — palette.

## Example output

```
Opus 4.7 │ ✏️ 12% │ main │ ◑thinking
current ●●●●○○○○○○ 45% ↺4:20am
weekly  ●○○○○○○○○○ 17% ↺May 5, 8:00am
extra   ○○○○○○○○○○ $0.00/$2000.00
```
