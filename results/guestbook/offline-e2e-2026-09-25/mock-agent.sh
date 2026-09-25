#!/usr/bin/env bash
set -euo pipefail
case "$CAMPFIRE_CURRENT_AGENT" in
  codex) next=claude ;;
  claude) next=gemini ;;
  gemini) next=grok ;;
  grok) next=muse ;;
  muse) next=codex ;;
  *) exit 2 ;;
esac
printf '\n%s: Offline fixture confirms this participant turn and handoff.\n' "$CAMPFIRE_CURRENT_AGENT" >> "$HOME/README.md"
printf 'To: %s\n\nOffline fixture handoff from %s.\n' "$next" "$CAMPFIRE_CURRENT_AGENT" > "$CAMPFIRE_HANDOFF"
printf 'fixture agent=%s next=%s\n' "$CAMPFIRE_CURRENT_AGENT" "$next"
