#!/usr/bin/env bash
set -euo pipefail
source /opt/campfire/lib.sh
prompt="$(handoff_prompt "${CAMPFIRE_INPUT_HANDOFF:?}")"
prompt="${prompt%$'\037'}"
if [[ "${CAMPFIRE_ASSISTANT_MODE:-0}" == "1" ]]; then
  # Docker already isolates the writable home; nested Bubblewrap cannot create
  # a user namespace in the default Docker Desktop container.
  exec codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check "$prompt"
fi
exec codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check "$prompt"
