#!/usr/bin/env bash
set -euo pipefail

# Kimi Code does not consume KIMI_API_KEY directly. Use its documented
# environment-model channel so Campfire can keep one credential-per-provider.
export KIMI_MODEL_NAME="${KIMI_MODEL_NAME:-kimi-for-coding}"
export KIMI_MODEL_API_KEY="${KIMI_MODEL_API_KEY:-${KIMI_API_KEY}}"
export KIMI_MODEL_PROVIDER_TYPE="${KIMI_MODEL_PROVIDER_TYPE:-kimi}"

exec kimi -p "Read ~/AGENTS.md and ~/README.md, inspect the existing home workspace, and take a useful autonomous turn. Before finishing, leave a handoff as instructed in AGENTS.md."
