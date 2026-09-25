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

participant_manually_verified() {
  local wanted="$1" name
  local -a names
  IFS=', ' read -r -a names <<< "${CAMPFIRE_MANUALLY_VERIFIED_AGENTS:-}"
  for name in "${names[@]}"; do
    [[ "$name" == "$wanted" ]] && return 0
  done
  return 1
}

participant_authenticated() {
  local name="$1"
  participant_manually_verified "$name" && return 0
  case "$name" in
    codex) codex login status >/dev/null 2>&1 ;;
    claude) [[ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]] || claude auth status 2>/dev/null | jq -e '.loggedIn == true' >/dev/null ;;
    gemini) [[ -n "${GEMINI_API_KEY:-}" || -s "$HOME/.gemini/oauth_creds.json" ]] ||
      { [[ "$(jq -r '.security.auth.selectedType // empty' "$HOME/.gemini/settings.json" 2>/dev/null)" == gemini-api-key ]] &&
        node /opt/campfire/gemini-auth-status.cjs; } ;;
    grok) [[ -s "${GROK_HOME:-$HOME/.grok}/auth.json" ]] ;;
    muse) [[ -n "${META_API_KEY:-}" ]] || { local auth_file="${XDG_CONFIG_HOME:-$HOME/.config}/muse/auth.json"; [[ -s "$auth_file" ]] && [[ "$(jq -r '.providers.meta.storage // empty' "$auth_file" 2>/dev/null)" != keychain ]]; } ;;
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

handoff_target() {
  local name=''
  IFS= read -r name < "$1" || [[ -n "$name" ]] || return 1
  [[ "$name" =~ ^[A-Za-z0-9_-]+$ ]] || return 1
  printf '%s\n' "$name" | tr '[:upper:]' '[:lower:]'
}
handoff_has_body() { awk 'NR > 1 && /[^[:space:]]/ { found=1 } END { exit !found }' "$1"; }
# The sentinel preserves trailing newlines through Bash command substitution.
handoff_prompt() {
  tail -n +2 "$1" || return 1
  printf '\037'
}
handoff_retarget() {
  { printf '%s\n' "$2"; tail -n +2 "$1"; } > "$3"
}
choose_first_available() {
  local exclude="${1:-}" name adapter
  while IFS='|' read -r name adapter; do
    if [[ "$name" != "$exclude" ]] && participant_enabled "$name" "$adapter"; then
      printf '%s\n' "$name"
      return 0
    fi
  done < <(participant_registry)
  return 1
}
is_available_name() { participant_adapter "$1" >/dev/null 2>&1; }
looks_temporarily_unavailable() { grep -Eiq '(rate.?limit|quota|usage.?limit|too many requests|429|temporar(il)?y unavailable|capacity|resource exhausted)' "$1"; }
