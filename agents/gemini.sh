#!/usr/bin/env bash
set -euo pipefail
if [[ "${CAMPFIRE_ASSISTANT_MODE:-0}" == "1" ]]; then
  prompt="You are temporarily assisting another Campfire participant. Work on this request independently and return your findings as your final answer. Do not create a handoff or communicate recursively. Request: ${CAMPFIRE_ASSIST_REQUEST}"
  exec gemini -p "$prompt" --skip-trust --approval-mode=yolo
fi
prompt="Read ~/AGENTS.md and ~/README.md, inspect the existing home workspace, and take a useful autonomous turn. Read the incoming context below. Before finishing, leave a handoff as instructed in AGENTS.md.\n\nIncoming context:\n${CAMPFIRE_INCOMING_CONTEXT:-None}"
if [[ "${CAMPFIRE_JSON_OUTPUT:-false}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  exec gemini -p "$prompt" --skip-trust --approval-mode=yolo --output-format stream-json
fi
gemini -p "$prompt" --skip-trust --approval-mode=yolo --output-format stream-json |
  node /opt/campfire/gemini-output.cjs
