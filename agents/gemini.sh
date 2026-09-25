#!/usr/bin/env bash
set -euo pipefail
source /opt/campfire/lib.sh
prompt="$(handoff_prompt "${CAMPFIRE_INPUT_HANDOFF:?}")"
prompt="${prompt%$'\037'}"
if [[ "${CAMPFIRE_ASSISTANT_MODE:-0}" == "1" ]]; then
  exec gemini -p "$prompt" --skip-trust --approval-mode=yolo
fi
if [[ "${CAMPFIRE_JSON_OUTPUT:-false}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  exec gemini -p "$prompt" --skip-trust --approval-mode=yolo --output-format stream-json
fi
gemini -p "$prompt" --skip-trust --approval-mode=yolo --output-format stream-json |
  node /opt/campfire/gemini-output.cjs
