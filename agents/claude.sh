#!/usr/bin/env bash
set -euo pipefail
if [[ "${CAMPFIRE_ASSISTANT_MODE:-0}" == "1" ]]; then
  prompt="You are temporarily assisting another Campfire participant. Work on this request independently and return your findings as your final answer. Do not create a handoff or communicate recursively. Request: ${CAMPFIRE_ASSIST_REQUEST}"
  exec claude -p --permission-mode bypassPermissions "$prompt"
fi
prompt="Read ~/AGENTS.md and ~/README.md, inspect the existing home workspace, and take a useful autonomous turn. Read the incoming context below. Before finishing, leave a handoff as instructed in AGENTS.md.\n\nIncoming context:\n${CAMPFIRE_INCOMING_CONTEXT:-None}"
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
