#!/usr/bin/env bash
# Codex usage/status script.
# Reads the latest ~/.codex/sessions JSONL token_count event and prints a
# compact status block suitable for tmux, starship custom modules, or watch.

set -u

CYAN=$'\033[38;2;79;195;247m'
ORANGE=$'\033[38;2;229;160;80m'
GREEN=$'\033[38;2;100;200;120m'
RED=$'\033[38;2;224;108;117m'
GRAY=$'\033[38;2;120;130;140m'
WHITE=$'\033[38;2;220;220;220m'
DIM=$'\033[2m'
RESET=$'\033[0m'

CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
SESSIONS_DIR="$CODEX_HOME/sessions"
DOTS=10

pick_color() {
  local pct=$1
  if [ "$pct" -ge 80 ] 2>/dev/null; then
    echo "$RED"
  elif [ "$pct" -ge 50 ] 2>/dev/null; then
    echo "$ORANGE"
  else
    echo "$GREEN"
  fi
}

dot_bar() {
  local pct=$1
  local dot_color=$2
  local filled=$(( pct * DOTS / 100 ))
  local bar=""
  local i
  for i in $(seq 1 "$DOTS"); do
    if [ "$i" -le "$filled" ]; then
      bar="${bar}${dot_color}●${RESET}"
    else
      bar="${bar}${GRAY}○${RESET}"
    fi
  done
  echo "$bar"
}

format_tokens() {
  local n=$1
  if [ "$n" -ge 1000000 ] 2>/dev/null; then
    awk -v n="$n" 'BEGIN { printf "%.1fm", n / 1000000 }'
  elif [ "$n" -ge 1000 ] 2>/dev/null; then
    awk -v n="$n" 'BEGIN { printf "%.0fk", n / 1000 }'
  else
    printf "%s" "$n"
  fi
}

format_reset() {
  local value=$1
  [ -z "$value" ] || [ "$value" = "null" ] && return 0

  if [[ "$value" =~ ^[0-9]+$ ]]; then
    TZ="${TZ:-Asia/Tokyo}" date -r "$value" "+%-I:%M%p" 2>/dev/null | tr 'A-Z' 'a-z'
    return 0
  fi

  local epoch=""
  epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${value:0:19}" "+%s" 2>/dev/null || true)
  [ -n "$epoch" ] && TZ="${TZ:-Asia/Tokyo}" date -r "$epoch" "+%-I:%M%p" 2>/dev/null | tr 'A-Z' 'a-z'
}

latest_rollout() {
  [ -d "$SESSIONS_DIR" ] || return 1

  shopt -s nullglob
  local files=("$SESSIONS_DIR"/*/*/*/*.jsonl)
  shopt -u nullglob
  [ "${#files[@]}" -gt 0 ] || return 1

  ls -t "${files[@]}" 2>/dev/null | head -n 1
}

rollout_path="${1:-}"
[ -n "$rollout_path" ] || rollout_path=$(latest_rollout || true)

if [ -z "$rollout_path" ] || [ ! -f "$rollout_path" ]; then
  printf "%sCodex%s %sno session data%s\n" "$CYAN" "$RESET" "$GRAY" "$RESET"
  exit 0
fi

token_event=$(jq -c 'select(.type == "event_msg" and .payload.type == "token_count" and .payload.info != null)' "$rollout_path" 2>/dev/null | tail -n 1)
turn_context=$(jq -c 'select(.type == "turn_context") | .payload' "$rollout_path" 2>/dev/null | tail -n 1)

if [ -z "$token_event" ]; then
  printf "%sCodex%s %sno token_count in %s%s\n" "$CYAN" "$RESET" "$GRAY" "$(basename "$rollout_path")" "$RESET"
  exit 0
fi

model=$(echo "$turn_context" | jq -r '.model // "codex"' 2>/dev/null)
effort=$(echo "$turn_context" | jq -r '.effort // .reasoning_effort // empty' 2>/dev/null)
cwd=$(echo "$turn_context" | jq -r '.cwd // empty' 2>/dev/null)

total_tokens=$(echo "$token_event" | jq -r '.payload.info.total_token_usage.total_tokens // 0')
input_tokens=$(echo "$token_event" | jq -r '.payload.info.total_token_usage.input_tokens // 0')
cached_tokens=$(echo "$token_event" | jq -r '.payload.info.total_token_usage.cached_input_tokens // 0')
output_tokens=$(echo "$token_event" | jq -r '.payload.info.total_token_usage.output_tokens // 0')
reasoning_tokens=$(echo "$token_event" | jq -r '.payload.info.total_token_usage.reasoning_output_tokens // 0')
context_tokens=$(echo "$token_event" | jq -r '.payload.info.last_token_usage.input_tokens // .payload.info.total_token_usage.input_tokens // 0')
context_window=$(echo "$token_event" | jq -r '.payload.info.model_context_window // 0')

ctx_pct=0
if [ "$context_window" -gt 0 ] 2>/dev/null; then
  ctx_pct=$(( context_tokens * 100 / context_window ))
fi

primary_pct=$(echo "$token_event" | jq -r '.payload.rate_limits.primary.used_percent // 0 | floor')
secondary_pct=$(echo "$token_event" | jq -r '.payload.rate_limits.secondary.used_percent // 0 | floor')
primary_reset_raw=$(echo "$token_event" | jq -r '.payload.rate_limits.primary.resets_at // empty')
secondary_reset_raw=$(echo "$token_event" | jq -r '.payload.rate_limits.secondary.resets_at // empty')
plan_type=$(echo "$token_event" | jq -r '.payload.rate_limits.plan_type // .payload.plan_type // empty')

branch=""
if [ -n "$cwd" ] && cd "$cwd" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
  branch=$(git symbolic-ref --short HEAD --no-lock 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || true)
fi

SEP="${GRAY} │ ${RESET}"
ctx_color=$(pick_color "$ctx_pct")
primary_color=$(pick_color "$primary_pct")
secondary_color=$(pick_color "$secondary_pct")

line1="${CYAN}${model}${RESET}"
[ -n "$effort" ] && line1+="${GRAY}/${effort}${RESET}"
line1+="${SEP}${GRAY}ctx ${RESET}${ctx_color}${ctx_pct}%${RESET}"
line1+=" ${GRAY}($(format_tokens "$context_tokens")/$(format_tokens "$context_window"))${RESET}"
[ -n "$branch" ] && line1+="${SEP}${WHITE}${branch}${RESET}"
[ -n "$plan_type" ] && line1+="${SEP}${DIM}${plan_type}${RESET}"

primary_bar=$(dot_bar "$primary_pct" "$primary_color")
secondary_bar=$(dot_bar "$secondary_pct" "$secondary_color")
primary_reset=$(format_reset "$primary_reset_raw")
secondary_reset=$(format_reset "$secondary_reset_raw")

line2="${GRAY}current ${RESET}${primary_bar} ${WHITE}${primary_pct}%${RESET}"
[ -n "$primary_reset" ] && line2+=" ${GRAY}↺${primary_reset}${RESET}"

line3="${GRAY}weekly  ${RESET}${secondary_bar} ${WHITE}${secondary_pct}%${RESET}"
[ -n "$secondary_reset" ] && line3+=" ${GRAY}↺${secondary_reset}${RESET}"

line4="${GRAY}session in $(format_tokens "$input_tokens")"
line4+=" / cached $(format_tokens "$cached_tokens")"
line4+=" / out $(format_tokens "$output_tokens")"
line4+=" / reasoning $(format_tokens "$reasoning_tokens")${RESET}"

printf "%s\n" "$line1"
printf "%s\n" "$line2"
printf "%s\n" "$line3"
printf "%s\n" "$line4"
