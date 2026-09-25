#!/usr/bin/env bash
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
container_name=campfire-setup
include_kimi=false
gemini_login=false
rebuild=false
recreate=false

usage() {
  cat <<'EOF'
Usage: ./setup.sh [--include-kimi] [--gemini-login] [--rebuild]

Reuse a working Campfire setup container and sign in to missing guestbook CLIs.
Gemini's login is part of its interactive CLI; --gemini-login opens that flow.
--rebuild refreshes the image and recreates the setup container. No model
prompts or research turns are run.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --include-kimi) include_kimi=true ;;
    --gemini-login) gemini_login=true ;;
    --rebuild) rebuild=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

if [[ ! -t 0 || ! -t 1 ]]; then
  echo 'Run setup.sh in an interactive terminal so the CLIs can show login links and accept codes.' >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo 'Docker is unavailable. Start Docker Desktop, then run ./setup.sh again.' >&2
  exit 1
fi

cd "$repo_dir"
umask 077
if [[ ! -f .env ]]; then
  cp .env.example .env
  echo 'Created .env from .env.example; edit research settings there before a run.'
fi
mkdir -p workspace logs

# Prepare the shared home before any login or research run. Keep user edits on
# subsequent setup runs; the controller has the same missing-file fallback.
if [[ ! -e workspace/AGENTS.md && ! -L workspace/AGENTS.md ]]; then
  cp templates/INTERNAL_AGENT_INSTRUCTIONS.md workspace/AGENTS.md
  echo 'Created workspace/AGENTS.md.'
fi
if [[ ! -e workspace/README.md && ! -L workspace/README.md ]]; then
  cp research/README.md workspace/README.md
  echo 'Created workspace/README.md.'
fi

# Older Campfire images lack the Muse file-backed credential setting. Upgrade
# those once, preserving the mounted home and all completed CLI logins.
if docker image inspect campfire >/dev/null 2>&1 && \
   ! docker image inspect campfire --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -Fxq 'TBH_CREDENTIAL_BACKEND=file'; then
  echo 'The existing image uses Muse keychain storage; rebuilding once for file-backed login.'
  rebuild=true
fi
if [[ "$rebuild" == true ]] || ! docker image inspect campfire >/dev/null 2>&1; then
  echo 'Building the Campfire image...'
  docker build -t campfire .
fi

# Keep a working setup container and its persistent home on ordinary reruns.
# --rebuild deliberately recreates it with the current image and .env. Gemini's
# file keychain derives its encryption key from this fixed container hostname.
if docker container inspect "$container_name" >/dev/null 2>&1; then
  existing_home="$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/home/campfire"}}{{.Source}}{{end}}{{end}}' "$container_name")"
  if [[ "$existing_home" != "$repo_dir/workspace" ]]; then
    echo "A different container already uses the name $container_name. Remove or rename it before rerunning setup.sh." >&2
    exit 1
  fi
  existing_hostname="$(docker inspect -f '{{.Config.Hostname}}' "$container_name")"
  if [[ "$existing_hostname" != campfire ]]; then
    echo 'Recreating the setup container with the stable Gemini keychain hostname.'
    recreate=true
  fi
  if [[ "$rebuild" == true || "$recreate" == true ]]; then
    if [[ "$(docker inspect -f '{{.State.Running}}' "$container_name")" == true ]] &&
       [[ "$(docker top "$container_name" -eo pid,args | tail -n +2 | wc -l | tr -d ' ')" -gt 1 ]]; then
      echo "An interactive shell or another process is still using $container_name. Exit it, then rerun ./setup.sh." >&2
      exit 1
    fi
    docker rm -f "$container_name" >/dev/null
  elif [[ "$(docker inspect -f '{{.State.Running}}' "$container_name")" != true ]]; then
    docker start "$container_name" >/dev/null
  fi
fi
if ! docker container inspect "$container_name" >/dev/null 2>&1; then
  docker run -d --name "$container_name" \
    --label dev.campfire.role=setup \
    --hostname campfire \
    --env-file "$repo_dir/.env" \
    -v "$repo_dir/workspace:/home/campfire" \
    --entrypoint sleep campfire infinity >/dev/null
else
  echo "Reusing $container_name and the existing Campfire image."
fi

if ! docker exec "$container_name" test -w /home/campfire; then
  echo 'The container cannot write workspace/. Fix its permissions and rerun setup.sh.' >&2
  exit 1
fi
docker exec "$container_name" mkdir -p \
  /home/campfire/.codex /home/campfire/.claude /home/campfire/.gemini \
  /home/campfire/.grok /home/campfire/.config /home/campfire/.local/share

authenticated() {
  local name="$1"
  if [[ "$name" == gemini && "$gemini_login" == true ]]; then
    docker exec "$container_name" bash -lc \
      'unset CAMPFIRE_MANUALLY_VERIFIED_AGENTS; source /opt/campfire/lib.sh; participant_authenticated gemini' >/dev/null 2>&1
  else
    docker exec "$container_name" bash -lc \
      "source /opt/campfire/lib.sh; participant_authenticated $name" >/dev/null 2>&1
  fi
}

login() {
  local name="$1" instruction="$2"
  shift 2
  if [[ "$name" != gemini || "$gemini_login" != true ]] && authenticated "$name"; then
    printf '\n%s: existing login found; skipping.\n' "$name"
    return
  fi

  printf '\n=== %s ===\n%s\n' "$name" "$instruction"
  # Each CLI writes its own credentials directly to the mounted home. Keep its
  # terminal attached so browser links, device codes and prompts stay visible.
  docker exec -it "$container_name" "$@" || true
  if authenticated "$name"; then
    printf '%s: login saved.\n' "$name"
  else
    printf '%s: login was not detected. Complete its prompt and rerun ./setup.sh.\n' "$name" >&2
    return 1
  fi
}

login codex 'Open the displayed device URL and enter its one-time code.' \
  codex login --device-auth
login claude 'Open the displayed Claude subscription login URL. Paste the authorization code here if requested.' \
  claude auth login --claudeai
if [[ "$gemini_login" != true ]] && authenticated gemini; then
  printf '\ngemini: existing login found; skipping.\n'
elif [[ "$gemini_login" == true ]]; then
  if ! login gemini 'If Gemini opens with an existing API key, type /auth first. Select Sign in with Google, complete its browser flow, then quit with /quit or Ctrl+C.' \
    env NO_BROWSER=true gemini --skip-trust; then
    echo 'Continuing with the remaining CLIs; Gemini can be retried later.'
  fi
else
  cat <<'EOF'

=== gemini ===
Gemini sign-in is inside its interactive CLI. Skipping that screen so setup
can continue. To complete it later, run ./setup.sh --gemini-login, or run:
  docker exec -it campfire-setup env NO_BROWSER=true gemini --skip-trust
If an API-key session opens, type /auth. Select Sign in with Google; after
login, quit with /quit or Ctrl+C.
EOF
fi
login grok 'Open the displayed xAI device URL and enter its one-time code.' \
  grok login --device-auth
login muse 'Open the displayed Meta device URL and enter its one-time code.' \
  env TBH_CREDENTIAL_BACKEND=file muse login
if [[ "$include_kimi" == true ]]; then
  login kimi 'Open the displayed Kimi device URL and enter its one-time code.' \
    kimi login
fi

echo
docker run --rm --env-file "$repo_dir/.env" \
  --hostname campfire \
  -v "$repo_dir/workspace:/home/campfire" \
  --entrypoint campfire-agents campfire
cat <<'EOF'

Setup steps finished. Login files are in workspace/ and the setup container
is running as campfire-setup. Complete any login-required participants before
the research run. Local checks cannot prove that a provider will accept a
later request. No research run was started.
See research/SETUP.md for the guestbook configuration and run command.
EOF
