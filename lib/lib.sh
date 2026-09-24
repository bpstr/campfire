#!/usr/bin/env bash
set -euo pipefail

participant_registry() {
  cat <<'EOF'
codex|/opt/campfire/agents/codex.sh
claude|/opt/campfire/agents/claude.sh
gemini|/opt/campfire/agents/gemini.sh
grok|/opt/campfire/agents/grok.sh
muse|/opt/campfire/agents/muse.sh
kimi|/opt/campfire/agents/kimi.sh
EOF
}

participant_installed() { [[ -x "$1" ]]; }

participant_authenticated() {
  local name="$1"
  case "$name" in
    codex) [[ -n "${CODEX_ACCESS_TOKEN:-}" || -s "${CODEX_HOME:-$HOME/.codex}/auth.json" ]] ;;
    claude) [[ -d "$HOME/.claude" ]] && find "$HOME/.claude" -maxdepth 2 -type f -size +0c 2>/dev/null | grep -q . ;;
    gemini) [[ -d "$HOME/.gemini" ]] && find "$HOME/.gemini" -maxdepth 2 -type f -size +0c 2>/dev/null | grep -q . ;;
    grok) [[ -s "${GROK_HOME:-$HOME/.grok}/auth.json" ]] ;;
    muse) [[ -d "${XDG_CONFIG_HOME:-$HOME/.config}/muse" || -d "${XDG_DATA_HOME:-$HOME/.local/share}/muse" ]] ;;
    kimi) [[ -d "${KIMI_CODE_HOME:-$HOME/.kimi-code}" ]] && find "${KIMI_CODE_HOME:-$HOME/.kimi-code}" -maxdepth 2 -type f -size +0c 2>/dev/null | grep -q . ;;
    *) return 1 ;;
  esac
}

participant_enabled() {
  local name="$1" adapter="$2"
  participant_installed "$adapter" && participant_authenticated "$name"
}

participant_adapter() {
  local wanted="$1"
  while IFS='|' read -r name adapter; do
    if [[ "$name" == "$wanted" ]] && participant_enabled "$name" "$adapter"; then printf '%s\n' "$adapter"; return 0; fi
  done < <(participant_registry)
  return 1
}

available_participants() {
  local exclude="${1:-}"
  while IFS='|' read -r name adapter; do
    if [[ "$name" != "$exclude" ]] && participant_enabled "$name" "$adapter"; then printf '%s\n' "$name"; fi
  done < <(participant_registry)
}

log_event() {
  local event="$1"; shift
  mkdir -p /var/log/campfire
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"ts":"%s","event":"%s"' "$ts" "$event" >> /var/log/campfire/events.jsonl
  while (( "$#" >= 2 )); do
    local key="$1" value="$2"; shift 2
    printf ',"%s":%s' "$key" "$(printf '%s' "$value" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" >> /var/log/campfire/events.jsonl
  done
  printf '}\n' >> /var/log/campfire/events.jsonl
}

handoff_target() { sed -nE 's/^[[:space:]]*To:[[:space:]]*([A-Za-z0-9_-]+)[[:space:]]*$/\1/p' "$1" | head -n1 | tr '[:upper:]' '[:lower:]'; }
choose_first_available() { available_participants "${1:-}" | head -n1; }
is_available_name() { available_participants "" | grep -Fxq "$1"; }
looks_temporarily_unavailable() { grep -Eiq '(rate.?limit|quota|usage.?limit|too many requests|429|temporar(il)?y unavailable|capacity|resource exhausted)' "$1"; }
