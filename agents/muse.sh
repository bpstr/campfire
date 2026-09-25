#!/usr/bin/env bash
set -euo pipefail
source /opt/campfire/lib.sh
prompt="$(handoff_prompt "${CAMPFIRE_INPUT_HANDOFF:?}")"
prompt="${prompt%$'\037'}"
if [[ "${CAMPFIRE_ASSISTANT_MODE:-0}" == "1" ]]; then
  exec muse exec --yolo "$prompt"
fi
if [[ "${CAMPFIRE_JSON_OUTPUT:-false}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  exec muse exec --yolo --json "$prompt"
fi
exec muse exec --yolo "$prompt"
