#!/usr/bin/env bash
set -euo pipefail

participant_registry() {
  cat <<'EOF'
codex|OPENAI_API_KEY|/opt/campfire/agents/codex.sh
claude|ANTHROPIC_API_KEY|/opt/campfire/agents/claude.sh
gemini|GEMINI_API_KEY|/opt/campfire/agents/gemini.sh
grok|XAI_API_KEY|/opt/campfire/agents/grok.sh
muse|META_API_KEY|/opt/campfire/agents/muse.sh
kimi|KIMI_API_KEY|/opt/campfire/agents/kimi.sh
EOF
}

participant_enabled() {
  local env_var="$1"
  [[ -n "${!env_var:-}" ]]
}

participant_installed() {
  local adapter="$1"
  [[ -x "$adapter" ]]
}

participant_adapter() {
  local wanted="$1"
  while IFS='|' read -r name env_var adapter; do
    if [[ "$name" == "$wanted" ]] && participant_enabled "$env_var" && participant_installed "$adapter"; then
      printf '%s\n' "$adapter"
      return 0
    fi
  done < <(participant_registry)
  return 1
}

available_participants() {
  local exclude="${1:-}"
  while IFS='|' read -r name env_var adapter; do
    if [[ "$name" != "$exclude" ]] && participant_enabled "$env_var" && participant_installed "$adapter"; then
      printf '%s\n' "$name"
    fi
  done < <(participant_registry)
}

json_escape() {
  python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

log_event() {
  local event="$1"
  shift
  mkdir -p /var/log/campfire
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","event":"%s"' "$ts" "$event" >> /var/log/campfire/events.jsonl
  while (( "$#" >= 2 )); do
    local key="$1" value="$2"
    shift 2
    local value_json
    value_json="$(printf '%s' "$value" | json_escape)"
    printf ',"%s":%s' "$key" "$value_json" >> /var/log/campfire/events.jsonl
  done
  printf '}\n' >> /var/log/campfire/events.jsonl
}

handoff_target() {
  local file="$1"
  sed -nE 's/^[[:space:]]*To:[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*$/\1/p' "$file" | head -n1 | tr '[:upper:]' '[:lower:]'
}

is_available_name() {
  local wanted="$1"
  available_participants "" | grep -Fxq "$wanted"
}

choose_first_available() {
  local exclude="${1:-}"
  available_participants "$exclude" | head -n1
}

looks_temporarily_unavailable() {
  local log_file="$1"
  grep -Eiq '(rate.?limit|quota|usage.?limit|too many requests|429|temporar(il)?y unavailable|capacity|resource exhausted)' "$log_file"
}
