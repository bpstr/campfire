#!/usr/bin/env bash
set -euo pipefail
source /opt/campfire/lib.sh

MAX_TURNS="${CAMPFIRE_MAX_TURNS:-100}"
TURN_TIMEOUT="${CAMPFIRE_TURN_TIMEOUT:-1800}"
UNAVAILABLE_POLICY="${CAMPFIRE_UNAVAILABLE_POLICY:-fallback}"
WAIT_SECONDS="${CAMPFIRE_WAIT_SECONDS:-900}"
ATTEMPT_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$-$RANDOM"

state_dir="$HOME/.campfire"
next_handoff="$state_dir/next"
outgoing_handoff="$state_dir/handoff"
mkdir -p /var/log/campfire/runs /var/log/campfire/handoffs "$state_dir/inbox"
CONTROLLER_LOG="/var/log/campfire/controller.log"
controller_log() { printf '%s [%s] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" | tee -a "$CONTROLLER_LOG" >&2; }
controller_log INFO "controller started pid=$$ attempt=$ATTEMPT_ID max_turns=$MAX_TURNS policy=$UNAVAILABLE_POLICY communication=${CAMPFIRE_COMMUNICATION_ENABLED:-false}"
/usr/local/bin/campfire-configure-mcp

[[ -f "$HOME/AGENTS.md" ]] || cp /opt/campfire/templates/INTERNAL_AGENT_INSTRUCTIONS.md "$HOME/AGENTS.md"
for client_file in CLAUDE.md GEMINI.md; do
  if [[ ! -e "$HOME/$client_file" && ! -L "$HOME/$client_file" ]]; then
    ln -s AGENTS.md "$HOME/$client_file"
  fi
done
if [[ ! -f "$HOME/README.md" ]]; then
  cp /opt/campfire/defaults/README.md "$HOME/README.md"
  [[ -e "$next_handoff" || -L "$next_handoff" ]] || cp /opt/campfire/defaults/START.md "$next_handoff"
fi

# Gemini's file keychain is encrypted with the container hostname. Catch the
# common setup/run hostname mismatch before any participant spends a turn.
if [[ -s "$HOME/.gemini/gemini-credentials.json" && -z "${GEMINI_API_KEY:-}" ]] &&
   [[ "$(hostname)" != campfire ]] &&
   jq -e '.security.auth.selectedType == "gemini-api-key"' "$HOME/.gemini/settings.json" >/dev/null 2>&1; then
  controller_log ERROR 'Gemini credentials require --hostname campfire; refusing to start with a different hostname'
  exit 8
fi

if [[ -n "${CAMPFIRE_INITIAL_AGENT:-}" ]]; then
  controller_log WARN 'CAMPFIRE_INITIAL_AGENT is ignored; the first line of ~/.campfire/next selects the participant'
fi
[[ -s "$next_handoff" ]] || { controller_log ERROR "initial handoff missing: $next_handoff"; exit 2; }

turn=1
while (( MAX_TURNS <= 0 || turn <= MAX_TURNS )); do
  current="$(handoff_target "$next_handoff" || true)"
  [[ -n "$current" ]] || { controller_log ERROR "invalid recipient in $next_handoff"; exit 5; }
  handoff_has_body "$next_handoff" || { controller_log ERROR "handoff text missing in $next_handoff"; exit 5; }
  adapter="$(participant_adapter "$current" || true)"
  if [[ -z "$adapter" ]]; then
    controller_log WARN "participant unavailable agent=$current"
    if [[ "$UNAVAILABLE_POLICY" == wait ]]; then
      sleep "$WAIT_SECONDS"
      continue
    fi
    [[ "$UNAVAILABLE_POLICY" == fallback ]] || exit 3
    next="$(choose_first_available "$current")"
    [[ -n "$next" ]] || exit 3
    handoff_retarget "$next_handoff" "$next" "$state_dir/next.$$.tmp"
    mv "$state_dir/next.$$.tmp" "$next_handoff"
    log_event routing.fallback requested "$current" executed "$next"
    continue
  fi

  rm -f "$outgoing_handoff"
  run_id="$(printf '%06d-%s-%s' "$turn" "$current" "$ATTEMPT_ID")"
  run_log="/var/log/campfire/runs/$run_id.log"

  export CAMPFIRE_CURRENT_AGENT="$current"
  export CAMPFIRE_INPUT_HANDOFF="$next_handoff"
  export CAMPFIRE_HANDOFF="$outgoing_handoff"
  export CAMPFIRE_RUN_ID="$run_id"

  controller_log INFO "run=$run_id state=PREPARED agent=$current adapter=$adapter"
  log_event run.prepared run "$run_id" agent "$current" adapter "$adapter"
  controller_log INFO "run=$run_id state=STARTING agent=$current"
  log_event run.starting run "$run_id" agent "$current"
  controller_log INFO "run=$run_id state=RUNNING agent=$current"
  log_event run.started run "$run_id" agent "$current"

  set +e
  timeout --signal=TERM --kill-after=15 "$TURN_TIMEOUT" "$adapter" </dev/null 2>&1 | tee "$run_log"
  status=${PIPESTATUS[0]}
  set -e

  controller_log INFO "run=$run_id state=FINISHING agent=$current exit=$status"
  log_event run.finishing run "$run_id" agent "$current" status "$status"
  log_event run.finished run "$run_id" agent "$current" status "$status"
  controller_log INFO "run=$run_id state=FINISHED agent=$current exit=$status"

  if (( status != 0 )) && looks_temporarily_unavailable "$run_log"; then
    controller_log WARN "run=$run_id agent=$current temporary_provider_limit"
    log_event participant.unavailable agent "$current" reason temporary_provider_limit
    if [[ "$UNAVAILABLE_POLICY" == wait ]]; then
      controller_log INFO "agent=$current waiting seconds=$WAIT_SECONDS"
      sleep "$WAIT_SECONDS"
      continue
    fi
    [[ "$UNAVAILABLE_POLICY" == fallback ]] || exit "$status"
    next="$(choose_first_available "$current")"; [[ -n "$next" ]] || exit "$status"
    handoff_retarget "$next_handoff" "$next" "$state_dir/next.$$.tmp"
    mv "$state_dir/next.$$.tmp" "$next_handoff"
    log_event routing.fallback requested "$current" executed "$next"
    continue
  fi

  if (( status != 0 )); then
    controller_log ERROR "run=$run_id agent=$current failed exit=$status"
    log_event run.failed run "$run_id" agent "$current" status "$status"
    exit "$status"
  fi

  [[ -s "$outgoing_handoff" ]] || { controller_log ERROR "run=$run_id handoff missing"; log_event handoff.missing run "$run_id" agent "$current"; exit 4; }
  target="$(handoff_target "$outgoing_handoff" || true)"
  archive="/var/log/campfire/handoffs/$run_id.txt"
  cp "$outgoing_handoff" "$archive"
  [[ -n "$target" ]] || { log_event handoff.invalid run "$run_id" reason missing_recipient; exit 5; }
  handoff_has_body "$outgoing_handoff" || { log_event handoff.invalid run "$run_id" reason empty_text; exit 5; }
  [[ "$target" != "$current" ]] || { log_event handoff.invalid run "$run_id" reason self_handoff; exit 6; }

  cp "$archive" "$state_dir/next.$$.tmp"
  mv "$state_dir/next.$$.tmp" "$next_handoff"

  if ! is_available_name "$target"; then
    log_event handoff.unavailable run "$run_id" requested "$target"
    if [[ "$UNAVAILABLE_POLICY" == stop ]]; then exit 7; fi
    if [[ "$UNAVAILABLE_POLICY" == fallback ]]; then
      next="$(choose_first_available "$current")"; [[ -n "$next" ]] || exit 7
      handoff_retarget "$next_handoff" "$next" "$state_dir/next.$$.tmp"
      mv "$state_dir/next.$$.tmp" "$next_handoff"
      log_event routing.fallback requested "$target" executed "$next"
      target="$next"
    fi
  fi

  controller_log INFO "run=$run_id state=HANDOFF_ACCEPTED from=$current to=$target"
  log_event handoff.accepted run "$run_id" from "$current" to "$target" archive "$archive"
  turn=$((turn + 1))
done

controller_log INFO "experiment finished reason=max_turns turns=$MAX_TURNS"
log_event experiment.finished reason max_turns turns "$MAX_TURNS"
