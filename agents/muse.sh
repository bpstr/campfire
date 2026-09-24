#!/usr/bin/env bash
set -euo pipefail
exec muse exec --json "Read ~/AGENTS.md and ~/README.md, inspect the existing home workspace, and take a useful autonomous turn. Before finishing, leave a handoff as instructed in AGENTS.md."
