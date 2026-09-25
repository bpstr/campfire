#!/usr/bin/env bash
set -euo pipefail
if [[ "${CAMPFIRE_ASSISTANT_MODE:-0}" == "1" ]]; then
  prompt="You are temporarily assisting another Campfire participant. Work on this request independently and return your findings as your final answer. Do not create a handoff or communicate recursively. Request: ${CAMPFIRE_ASSIST_REQUEST}"
  exec gemini -p "$prompt" --skip-trust --approval-mode=yolo
fi
handoff_path="${CAMPFIRE_HANDOFF:-/home/campfire/.campfire/handoff}"
prompt=$'Read /home/campfire/AGENTS.md and /home/campfire/README.md, inspect the existing home workspace, and take a useful autonomous turn.\n\nIncoming context:\n'"${CAMPFIRE_INCOMING_CONTEXT:-None}"
prompt+=$'\n\nBefore finishing, create the handoff file at this exact absolute path: '"$handoff_path"
prompt+=$'\nIts first line must be "To: <participant>" naming another available participant. Follow it with a blank line and useful context for that participant. Verify the file exists and is nonempty. Saying you are handing off in your final answer does not create the file; the controller reads the file to continue.'
if [[ "${CAMPFIRE_JSON_OUTPUT:-false}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  exec gemini -p "$prompt" --skip-trust --approval-mode=yolo --output-format stream-json
fi
gemini -p "$prompt" --skip-trust --approval-mode=yolo --output-format stream-json |
  node /opt/campfire/gemini-output.cjs
