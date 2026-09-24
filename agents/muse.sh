#!/usr/bin/env bash
set -euo pipefail
if [[ "${CAMPFIRE_ASSISTANT_MODE:-0}" == "1" ]]; then
  prompt="You are temporarily assisting another Campfire participant. Work on this request independently and return your findings as your final answer. Do not create a handoff. Do not modify the shared workspace. Request: ${CAMPFIRE_ASSIST_REQUEST}"
  exec muse exec "$prompt"
fi
prompt="Read ~/AGENTS.md and ~/README.md, inspect the existing home workspace, and take a useful autonomous turn. Read any incoming handoff and messages supplied below. Before finishing, leave a handoff as instructed in AGENTS.md.\n\nIncoming context:\n${CAMPFIRE_INCOMING_CONTEXT:-None}"
exec muse exec --json "$prompt"
