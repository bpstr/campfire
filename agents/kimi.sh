#!/usr/bin/env bash
set -euo pipefail
source /opt/campfire/lib.sh
prompt="$(handoff_prompt "${CAMPFIRE_INPUT_HANDOFF:?}")"
prompt="${prompt%$'\037'}"
exec kimi -p "$prompt"
