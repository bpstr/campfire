#!/usr/bin/env bash
set -euo pipefail
export KIMI_MODEL_NAME="${KIMI_MODEL_NAME:-kimi-for-coding}"
export KIMI_MODEL_API_KEY="${KIMI_MODEL_API_KEY:-${KIMI_API_KEY}}"
export KIMI_MODEL_PROVIDER_TYPE="${KIMI_MODEL_PROVIDER_TYPE:-kimi}"
if [[ "${CAMPFIRE_ASSISTANT_MODE:-0}" == "1" ]]; then
  prompt="You are temporarily assisting another Campfire participant. Work on this request independently and return your findings as your final answer. Do not create a handoff. Do not modify the shared workspace. Request: ${CAMPFIRE_ASSIST_REQUEST}"
else
  prompt="Read ~/AGENTS.md and ~/README.md, inspect the existing home workspace, and take a useful autonomous turn. Read any incoming handoff and messages supplied below. Before finishing, leave a handoff as instructed in AGENTS.md.\n\nIncoming context:\n${CAMPFIRE_INCOMING_CONTEXT:-None}"
fi
exec kimi -p "$prompt"
