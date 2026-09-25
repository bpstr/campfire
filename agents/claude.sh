#!/usr/bin/env bash
set -euo pipefail
source /opt/campfire/lib.sh
prompt="$(handoff_prompt "${CAMPFIRE_INPUT_HANDOFF:?}")"
prompt="${prompt%$'\037'}"
if [[ "${CAMPFIRE_ASSISTANT_MODE:-0}" == "1" ]]; then
  exec claude -p --permission-mode bypassPermissions "$prompt"
fi
if [[ "${CAMPFIRE_COMMUNICATION_ENABLED:-false}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  if [[ "${CAMPFIRE_JSON_OUTPUT:-false}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
    exec claude -p --permission-mode bypassPermissions --mcp-config /opt/campfire/mcp/providers/claude.json --output-format stream-json --verbose "$prompt"
  fi
  exec claude -p --permission-mode bypassPermissions --mcp-config /opt/campfire/mcp/providers/claude.json "$prompt"
fi
if [[ "${CAMPFIRE_JSON_OUTPUT:-false}" =~ ^(1|true|TRUE|yes|YES|on|ON)$ ]]; then
  exec claude -p --permission-mode bypassPermissions --output-format stream-json --verbose "$prompt"
fi
exec claude -p --permission-mode bypassPermissions "$prompt"
