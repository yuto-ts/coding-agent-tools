#!/usr/bin/env bash
# Claude Code Status Line Script
# Style: cyan model | dot bars for current/weekly/extra usage

# ── ANSI colors ──────────────────────────────────────────────────────────────
CYAN=$'\033[38;2;79;195;247m'
ORANGE=$'\033[38;2;229;160;80m'
GREEN=$'\033[38;2;100;200;120m'
RED=$'\033[38;2;224;108;117m'
GRAY=$'\033[38;2;120;130;140m'
WHITE=$'\033[38;2;220;220;220m'
DIM=$'\033[2m'
RESET=$'\033[0m'

# ── Read stdin JSON ───────────────────────────────────────────────────────────
INPUT=$(cat)

MODEL_DISPLAY=$(echo "$INPUT" | jq -r '.model.display_name // "Unknown"')
USED_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0 | floor')
CWD=$(echo "$INPUT" | jq -r '.workspace.current_dir // .cwd // ""')

# ── Color selector ────────────────────────────────────────────────────────────
pick_color() {
  local pct=$1
  if [ "$pct" -ge 80 ]; then
    echo "$RED"
  elif [ "$pct" -ge 50 ]; then
    echo "$ORANGE"
  else
    echo "$GREEN"
  fi
}

pick_ctx_color() {
  local pct=$1
  if [ "$pct" -ge 80 ]; then
    echo "$RED"
  elif [ "$pct" -ge 50 ]; then
    echo "$ORANGE"
  else
    echo "$GRAY"
  fi
}

# ── Dot progress bar (10 dots) ────────────────────────────────────────────────
dot_bar() {
  local pct=$1
  local dot_color=$2
  local filled=$(( pct * 10 / 100 ))
  local bar=""
  for i in $(seq 1 10); do
    if [ "$i" -le "$filled" ]; then
      bar="${bar}${dot_color}●${RESET}"
    else
      bar="${bar}${GRAY}○${RESET}"
    fi
  done
  echo "$bar"
}

# ── Git branch ────────────────────────────────────────────────────────────────
GIT_BRANCH=""
if [ -n "$CWD" ] && cd "$CWD" 2>/dev/null; then
  if git rev-parse --git-dir >/dev/null 2>&1; then
    GIT_BRANCH=$(git symbolic-ref --short HEAD --no-lock 2>/dev/null \
      || git rev-parse --short HEAD 2>/dev/null || echo "")
  fi
fi

# ── Rate limit cache ──────────────────────────────────────────────────────────
# Usage windows are 5h / 7d so a long TTL is fine; the API has its own rate
# limit and statusline runs frequently, so we refresh sparingly.
CACHE_FILE="/tmp/claude-usage-cache.json"
ERROR_FILE="/tmp/claude-usage-cache.error"
CACHE_TTL=300        # 5 min between successful refreshes
ERROR_BACKOFF=300    # after a failed/rate-limited fetch, wait 5 min before retrying
CURRENT_PCT=0
WEEKLY_PCT=0
CURRENT_RESET=""
WEEKLY_RESET=""
EXTRA_USED_DOLLARS=""
EXTRA_TOTAL_DOLLARS=""
RESETS_DATE=""

fetch_usage() {
  local TOKEN
  TOKEN=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
  [ -z "$TOKEN" ] && return 1

  local ACCESS_TOKEN
  ACCESS_TOKEN=$(echo "$TOKEN" | jq -r '.claudeAiOauth.accessToken // .accessToken // empty' 2>/dev/null)
  [ -z "$ACCESS_TOKEN" ] && ACCESS_TOKEN="$TOKEN"

  local RESPONSE
  RESPONSE=$(curl -s --max-time 5 \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)

  # Only cache responses that look like real usage data. Rate-limit / error
  # bodies must not overwrite the previous good cache, otherwise the display
  # gets stuck showing zeros until the bad cache expires.
  if [ -z "$RESPONSE" ] || ! echo "$RESPONSE" | jq -e '.five_hour' >/dev/null 2>&1; then
    : > "$ERROR_FILE"
    return 1
  fi

  echo "$RESPONSE" > "$CACHE_FILE"
  rm -f "$ERROR_FILE"
}

load_usage() {
  local NOW
  NOW=$(date +%s)
  local CACHE_VALID=0
  local IN_BACKOFF=0

  if [ -f "$CACHE_FILE" ]; then
    local CACHE_MTIME
    CACHE_MTIME=$(stat -f %m "$CACHE_FILE" 2>/dev/null \
      || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
    local AGE=$(( NOW - CACHE_MTIME ))
    [ "$AGE" -lt "$CACHE_TTL" ] && CACHE_VALID=1
  fi

  if [ -f "$ERROR_FILE" ]; then
    local ERR_MTIME
    ERR_MTIME=$(stat -f %m "$ERROR_FILE" 2>/dev/null \
      || stat -c %Y "$ERROR_FILE" 2>/dev/null || echo 0)
    local ERR_AGE=$(( NOW - ERR_MTIME ))
    [ "$ERR_AGE" -lt "$ERROR_BACKOFF" ] && IN_BACKOFF=1
  fi

  [ "$CACHE_VALID" -eq 0 ] && [ "$IN_BACKOFF" -eq 0 ] && fetch_usage

  if [ -f "$CACHE_FILE" ]; then
    local DATA
    DATA=$(cat "$CACHE_FILE")

    # API returns utilization as 0..100 (not 0..1)
    CURRENT_PCT=$(echo "$DATA" | jq -r '.five_hour.utilization // 0 | floor' 2>/dev/null || echo 0)
    WEEKLY_PCT=$(echo "$DATA" | jq -r '.seven_day.utilization // 0 | floor' 2>/dev/null || echo 0)

    # Extra usage values are returned in cents even though currency is USD.
    EXTRA_USED_DOLLARS=$(echo "$DATA" | jq -r '.extra_usage.used_credits // empty' 2>/dev/null || echo "")
    EXTRA_TOTAL_DOLLARS=$(echo "$DATA" | jq -r '.extra_usage.monthly_limit // empty' 2>/dev/null || echo "")

    # 5-hour reset time (Asia/Tokyo). API timestamps are ISO 8601 with offset
    # like "2026-05-04T19:20:00.602676+00:00" — strip fractional seconds + tz.
    local FH_UTC
    FH_UTC=$(echo "$DATA" | jq -r '.five_hour.resets_at // empty' 2>/dev/null)
    if [ -n "$FH_UTC" ]; then
      local FH_EPOCH
      FH_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${FH_UTC:0:19}" "+%s" 2>/dev/null)
      if [ -n "$FH_EPOCH" ]; then
        CURRENT_RESET=$(TZ="Asia/Tokyo" date -r "$FH_EPOCH" "+%-I:%M%p" 2>/dev/null || echo "")
        CURRENT_RESET=$(echo "$CURRENT_RESET" | tr 'A-Z' 'a-z')
      fi
    fi

    # 7-day reset time (Asia/Tokyo)
    local SD_UTC
    SD_UTC=$(echo "$DATA" | jq -r '.seven_day.resets_at // empty' 2>/dev/null)
    if [ -n "$SD_UTC" ]; then
      local SD_EPOCH
      SD_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${SD_UTC:0:19}" "+%s" 2>/dev/null)
      if [ -n "$SD_EPOCH" ]; then
        WEEKLY_RESET=$(TZ="Asia/Tokyo" date -r "$SD_EPOCH" "+%b %-d, %-I:%M%p" 2>/dev/null || echo "")
        WEEKLY_RESET=$(echo "$WEEKLY_RESET" | tr 'A-Z' 'a-z')
      fi
    fi
  fi
}

load_usage

# ── Line 1: model | context% | branch | thinking ─────────────────────────────
SEP="${GRAY} │ ${RESET}"
CTX_COLOR=$(pick_ctx_color "$USED_PCT")

LINE1="${CYAN}${MODEL_DISPLAY}${RESET}"
LINE1+="${SEP}${GRAY}✏️  ${RESET}${CTX_COLOR}${USED_PCT}%${RESET}"

if [ -n "$GIT_BRANCH" ]; then
  LINE1+="${SEP}${WHITE}${GIT_BRANCH}${RESET}"
fi

LINE1+="${SEP}${DIM}${GRAY}◑thinking${RESET}"

# ── Line 2: current (5-hour) ──────────────────────────────────────────────────
CR_COLOR=$(pick_color "$CURRENT_PCT")
CR_BAR=$(dot_bar "$CURRENT_PCT" "$CR_COLOR")

LINE2="${GRAY}current ${RESET}${CR_BAR} ${WHITE}${CURRENT_PCT}%${RESET}"
if [ -n "$CURRENT_RESET" ]; then
  LINE2+=" ${GRAY}↺${CURRENT_RESET}${RESET}"
fi

# ── Line 3: weekly (7-day) ────────────────────────────────────────────────────
WK_COLOR=$(pick_color "$WEEKLY_PCT")
WK_BAR=$(dot_bar "$WEEKLY_PCT" "$WK_COLOR")

LINE3="${GRAY}weekly  ${RESET}${WK_BAR} ${WHITE}${WEEKLY_PCT}%${RESET}"
if [ -n "$WEEKLY_RESET" ]; then
  LINE3+=" ${GRAY}↺${WEEKLY_RESET}${RESET}"
fi

# ── Line 4: extra credits (if available) ──────────────────────────────────────
LINE4=""
if [ -n "$EXTRA_USED_DOLLARS" ] && [ -n "$EXTRA_TOTAL_DOLLARS" ]; then
  EXTRA_PCT=0
  TOTAL_INT=$(echo "$EXTRA_TOTAL_DOLLARS" | awk '{printf "%d", $1}')
  USED_INT=$(echo "$EXTRA_USED_DOLLARS" | awk '{printf "%d", $1}')
  if [ "$TOTAL_INT" -gt 0 ] 2>/dev/null; then
    EXTRA_PCT=$(( USED_INT * 100 / TOTAL_INT ))
  fi
  EX_COLOR=$(pick_color "$EXTRA_PCT")
  EX_BAR=$(dot_bar "$EXTRA_PCT" "$EX_COLOR")
  USED_FMT=$(awk -v cents="$EXTRA_USED_DOLLARS" 'BEGIN { printf "$%.2f", cents / 100 }')
  TOTAL_FMT=$(awk -v cents="$EXTRA_TOTAL_DOLLARS" 'BEGIN { printf "$%.2f", cents / 100 }')
  LINE4="${GRAY}extra   ${RESET}${EX_BAR} ${WHITE}${USED_FMT}/${TOTAL_FMT}${RESET}"
fi

# ── Line 5: resets date ───────────────────────────────────────────────────────
LINE5=""
if [ -n "$RESETS_DATE" ]; then
  LINE5="${GRAY}resets ${RESETS_DATE}${RESET}"
fi

# ── Output ────────────────────────────────────────────────────────────────────
printf "%s\n" "${LINE1}"
printf "%s\n" "${LINE2}"
printf "%s\n" "${LINE3}"
[ -n "$LINE4" ] && printf "%s\n" "${LINE4}"
[ -n "$LINE5" ] && printf "%s\n" "${LINE5}"
exit 0
