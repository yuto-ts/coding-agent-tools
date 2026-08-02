#!/usr/bin/env bash
# RunCat Neo custom metrics updater.
# Writes ~/.runcat/claude-usage.json and ~/.runcat/codex-usage.json in the
# RunCat Neo custom-metrics format (https://zenn.dev/kyome/articles/eb4a9f664002ad).
# RunCat is file-watch based: it re-renders whenever these files change.
#
# Data sources (same as coding-agent-tools/*/statusline):
#   Claude: Keychain "Claude Code-credentials" -> https://api.anthropic.com/api/oauth/usage
#   Codex:  latest ~/.codex/sessions/**/*.jsonl token_count event (no network)

set -u

OUT_DIR="${RUNCAT_METRICS_DIR:-$HOME/.runcat}"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
TZ_DISPLAY="${TZ_DISPLAY:-Asia/Tokyo}"

mkdir -p "$OUT_DIR"

now_iso() {
  date -u "+%Y-%m-%dT%H:%M:%SZ"
}

# ISO 8601 (with or without fractional seconds/offset) or epoch -> "7:30pm" / "jul 21, 7:30pm"
format_reset() {
  local value=$1 fmt=$2 epoch=""
  [ -z "$value" ] || [ "$value" = "null" ] && return 0
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    epoch=$value
  else
    epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${value:0:19}" "+%s" 2>/dev/null || true)
  fi
  [ -n "$epoch" ] && TZ="$TZ_DISPLAY" date -r "$epoch" "+$fmt" 2>/dev/null | tr 'A-Z' 'a-z'
}

# metric_row <title> <pct> <reset> -> emits one metrics[] object as JSON
metric_row() {
  local title=$1 pct=$2 reset=$3
  local fv="${pct}%"
  [ -n "$reset" ] && fv="${pct}%  ↺ ${reset}"
  jq -nc --arg t "$title" --arg fv "$fv" \
    --argjson nv "$(awk -v p="$pct" 'BEGIN { printf "%.4f", p / 100 }')" \
    '{ title: $t, formattedValue: $fv, normalizedValue: $nv }'
}

# write_metric <out-file> <title> <symbol> <bar-value> <updated-iso> <row-json>...
write_metric() {
  local out=$1 title=$2 symbol=$3 bar=$4 updated=$5
  shift 5
  [ -z "$updated" ] && updated=$(now_iso)
  local rows
  rows=$(printf '%s\n' "$@" | jq -sc '.')
  jq -n \
    --arg title "$title" \
    --arg symbol "$symbol" \
    --arg bar "$bar" \
    --argjson metrics "$rows" \
    --arg updated "$updated" \
    '{
      title: $title,
      symbol: $symbol,
      metricsBarValue: $bar,
      metrics: $metrics,
      lastUpdatedDate: $updated
    }' > "${out}.tmp" && mv "${out}.tmp" "$out"
}

# ── Claude ────────────────────────────────────────────────────────────────────
KEYCHAIN_SERVICE="Claude Code-credentials"
OAUTH_CLIENT_ID="9d1c250a-e61b-44d9-88ed-5944d1962f5e"  # Claude Code public client id

# Prints a valid access token. Starts trying to refresh 60 min before expiry —
# retrying each tick, because the token endpoint's shared rate limit means any
# single attempt often 429s — and keeps serving the old token until it truly
# expires. Rotated credentials are written back to the Keychain in the same
# JSON shape so Claude Code keeps working.
claude_access_token() {
  local creds access expires_at refresh now refreshed new_creds
  creds=$(security find-generic-password -s "$KEYCHAIN_SERVICE" -w 2>/dev/null) || return 1

  access=$(echo "$creds" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
  expires_at=$(echo "$creds" | jq -r '.claudeAiOauth.expiresAt // 0' 2>/dev/null)
  now=$(( $(date +%s) * 1000 ))

  if [ -n "$access" ] && [ "$expires_at" -gt $(( now + 3600000 )) ] 2>/dev/null; then
    echo "$access"
    return 0
  fi

  # Inside the refresh window the old token may still be good for a while;
  # serve it whenever refresh is unavailable instead of failing outright.
  local usable=""
  if [ -n "$access" ] && [ "$expires_at" -gt $(( now + 60000 )) ] 2>/dev/null; then
    usable=$access
  fi

  refresh=$(echo "$creds" | jq -r '.claudeAiOauth.refreshToken // empty' 2>/dev/null)
  if [ -z "$refresh" ]; then
    [ -n "$usable" ] && { echo "$usable"; return 0; }
    return 1
  fi

  # The token endpoint rate-limits hard (~1 call / 4h per anthropics/claude-code
  # #38248), and the budget is shared with the `claude` CLI's own refresh.
  # After a 429 back off 30 min — short enough that repeated attempts across
  # the 60-min refresh window (and beyond) eventually land one, long enough
  # not to hog the budget. invalid_grant means the refresh token itself is
  # dead; retrying is useless until the user re-logins, so back off 6h.
  local backoff_file="$OUT_DIR/.claude-refresh-fail"
  if [ -f "$backoff_file" ]; then
    local age=$(( $(date +%s) - $(stat -f %m "$backoff_file" 2>/dev/null || echo 0) ))
    local wait=1800
    grep -q invalid_grant "$backoff_file" 2>/dev/null && wait=21600
    if [ "$age" -lt "$wait" ]; then
      [ -n "$usable" ] && { echo "$usable"; return 0; }
      return 1
    fi
  fi

  local host
  for host in platform.claude.com console.anthropic.com; do
    refreshed=$(curl -s --max-time 10 -X POST \
      -H "Content-Type: application/json" \
      -d "{\"grant_type\":\"refresh_token\",\"refresh_token\":\"${refresh}\",\"client_id\":\"${OAUTH_CLIENT_ID}\"}" \
      "https://${host}/v1/oauth/token" 2>/dev/null)
    echo "$refreshed" | jq -e '.access_token' >/dev/null 2>&1 && break
    echo "[$(now_iso)] refresh via $host failed: $(echo "$refreshed" | jq -c 'del(.access_token, .refresh_token)' 2>/dev/null || echo "unparseable")" >&2
  done
  if ! echo "$refreshed" | jq -e '.access_token' >/dev/null 2>&1; then
    if echo "$refreshed" | grep -q invalid_grant; then
      echo invalid_grant > "$backoff_file"
    else
      echo rate_limited > "$backoff_file"
    fi
    [ -n "$usable" ] && { echo "$usable"; return 0; }
    return 1
  fi
  rm -f "$backoff_file"

  new_creds=$(echo "$creds" | jq -c \
    --argjson r "$refreshed" \
    --argjson now "$now" \
    '.claudeAiOauth.accessToken = $r.access_token
     | .claudeAiOauth.refreshToken = ($r.refresh_token // .claudeAiOauth.refreshToken)
     | .claudeAiOauth.expiresAt = ($now + ($r.expires_in // 3600) * 1000)')

  security add-generic-password -U -s "$KEYCHAIN_SERVICE" -a "$USER" -w "$new_creds" 2>/dev/null

  echo "$refreshed" | jq -r '.access_token'
}

# Cache written by coding-agent-tools/claude-code/statusline (refreshed while
# the Claude Code CLI is in use). Fallback when the OAuth refresh is 429'd.
STATUSLINE_CACHE="/tmp/claude-usage-cache.json"

# `claude login` is a browser OAuth flow that needs a real person to approve it,
# so a launchd job can never complete it unattended. The best we can do is
# detect the dead-auth state and tell the user to re-login. Throttled, because
# a broken token would otherwise fire a banner every 5 minutes.
NOTIFY_STAMP="$OUT_DIR/.claude-auth-notified"
NOTIFY_INTERVAL=21600  # 6h

notify_auth_needed() {
  if [ -f "$NOTIFY_STAMP" ]; then
    local age=$(( $(date +%s) - $(stat -f %m "$NOTIFY_STAMP" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$NOTIFY_INTERVAL" ] && return 0
  fi
  : > "$NOTIFY_STAMP"

  echo "[$(now_iso)] claude: auth dead -> notifying user to re-login" >&2
  osascript -e 'display notification "ターミナルで claude を起動し /login を実行してください" with title "RunCat: Claude の認証が切れています" sound name "Basso"' >/dev/null 2>&1

  # Opt-in (RUNCAT_AUTO_LOGIN=1): open Terminal on the login flow. Still needs
  # the user to finish it in the browser -- this only saves typing.
  if [ "${RUNCAT_AUTO_LOGIN:-0}" = "1" ]; then
    osascript -e 'tell application "Terminal" to do script "claude login"' \
              -e 'tell application "Terminal" to activate' >/dev/null 2>&1
  fi
}

update_claude() {
  local access response
  if access=$(claude_access_token) && [ -n "$access" ]; then
    response=$(curl -s --max-time 10 \
      -H "Authorization: Bearer ${access}" \
      -H "Content-Type: application/json" \
      -H "anthropic-version: 2023-06-01" \
      -H "anthropic-beta: oauth-2025-04-20" \
      "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
  else
    response=""
  fi

  # Fall back to the statusline cache; don't overwrite a good file with errors.
  # Stamp the JSON with the cache's mtime so staleness is visible in RunCat.
  # Only a rejected refresh token (invalid_grant) means the login is actually
  # dead and needs the user; a rate-limited refresh is just a temporary stall.
  local updated="" auth_dead=0 stale_age=""
  if echo "$response" | jq -e '.five_hour' >/dev/null 2>&1; then
    rm -f "$NOTIFY_STAMP"   # live data == auth is healthy again
  else
    if grep -q invalid_grant "$OUT_DIR/.claude-refresh-fail" 2>/dev/null; then
      auth_dead=1
      notify_auth_needed
    fi
    if [ -f "$STATUSLINE_CACHE" ] && jq -e '.five_hour' "$STATUSLINE_CACHE" >/dev/null 2>&1; then
      local cache_mtime
      cache_mtime=$(stat -f %m "$STATUSLINE_CACHE")
      response=$(cat "$STATUSLINE_CACHE")
      updated=$(date -u -r "$cache_mtime" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)
      stale_age=$(awk -v s=$(( $(date +%s) - cache_mtime )) 'BEGIN { printf "%.1fh", s / 3600 }')
      echo "[$(now_iso)] claude: using statusline cache fallback ($updated)" >&2
    else
      return 1
    fi
  fi

  local p5 pw r5 rw
  p5=$(echo "$response" | jq -r '.five_hour.utilization // 0 | floor')
  pw=$(echo "$response" | jq -r '.seven_day.utilization // 0 | floor')
  r5=$(format_reset "$(echo "$response" | jq -r '.five_hour.resets_at // empty')" "%-I:%M%p")
  rw=$(format_reset "$(echo "$response" | jq -r '.seven_day.resets_at // empty')" "%b %-d, %-I:%M%p")

  # Fable weekly limit lives in limits[] as a model-scoped entry, not a
  # top-level field. Missing on some plans/responses -> skip the row.
  local pf rf
  pf=$(echo "$response" | jq -r '[.limits[]? | select(.scope.model.display_name == "Fable")][0].percent // empty | floor')
  rf=$(format_reset "$(echo "$response" | jq -r '[.limits[]? | select(.scope.model.display_name == "Fable")][0].resets_at // empty')" "%b %-d, %-I:%M%p")

  local rows=(
    "$(metric_row "5h" "$p5" "$r5")"
    "$(metric_row "Weekly" "$pw" "$rw")"
  )
  [ -n "$pf" ] && rows+=("$(metric_row "Fable" "$pf" "$rf")")

  # Make degraded data visible in the dashboard instead of silently showing
  # stale cache numbers as if they were current.
  local bar="C ${p5}%"
  if [ "$auth_dead" -eq 1 ]; then
    bar="C ⚠️"
    rows+=("$(jq -nc '{ title: "⚠️ 認証切れ", formattedValue: "claude /login が必要" }')")
  elif [ -n "$stale_age" ]; then
    bar="C ${p5}%~"
    rows+=("$(jq -nc --arg v "${stale_age} 前のキャッシュ" '{ title: "⏳ stale", formattedValue: $v }')")
  fi

  write_metric "$OUT_DIR/claude-usage.json" "Claude" "asterisk" "$bar" \
    "$updated" "${rows[@]}"
}

# ── Codex ─────────────────────────────────────────────────────────────────────
update_codex() {
  [ -d "$CODEX_HOME/sessions" ] || return 1
  shopt -s nullglob
  local files=("$CODEX_HOME/sessions"/*/*/*/*.jsonl)
  shopt -u nullglob
  [ "${#files[@]}" -gt 0 ] || return 1

  # Newest session may lack rate_limits events; scan the 10 most recent.
  local rollout event=""
  while IFS= read -r rollout; do
    event=$(jq -c 'select(.type == "event_msg" and .payload.type == "token_count" and .payload.rate_limits != null)' \
      "$rollout" 2>/dev/null | tail -n 1)
    [ -n "$event" ] && break
  done < <(ls -t "${files[@]}" 2>/dev/null | head -n 10)
  [ -z "$event" ] && return 1

  local p5 pw r5 rw updated
  p5=$(echo "$event" | jq -r '.payload.rate_limits.primary.used_percent // 0 | floor')
  pw=$(echo "$event" | jq -r '.payload.rate_limits.secondary.used_percent // 0 | floor')
  r5=$(format_reset "$(echo "$event" | jq -r '.payload.rate_limits.primary.resets_at // empty')" "%-I:%M%p")
  rw=$(format_reset "$(echo "$event" | jq -r '.payload.rate_limits.secondary.resets_at // empty')" "%b %-d, %-I:%M%p")
  # Data is only as fresh as the last Codex session, so stamp with its mtime.
  updated=$(date -u -r "$(stat -f %m "$rollout")" "+%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

  write_metric "$OUT_DIR/codex-usage.json" "Codex" "terminal" "X ${p5}%" \
    "$updated" \
    "$(metric_row "5h" "$p5" "$r5")" \
    "$(metric_row "Weekly" "$pw" "$rw")"
}

update_claude
claude_rc=$?
update_codex
codex_rc=$?

# Exit 0 if at least one metric updated; launchd treats nonzero as failure noise.
[ "$claude_rc" -eq 0 ] || [ "$codex_rc" -eq 0 ]
