#!/usr/bin/env bash
set -euo pipefail
source /opt/campfire/lib.sh

MAX_TURNS="${CAMPFIRE_MAX_TURNS:-100}"
TURN_TIMEOUT="${CAMPFIRE_TURN_TIMEOUT:-1800}"
UNAVAILABLE_POLICY="${CAMPFIRE_UNAVAILABLE_POLICY:-fallback}"
WAIT_SECONDS="${CAMPFIRE_WAIT_SECONDS:-900}"

mkdir -p /var/log/campfire/runs /var/log/campfire/handoffs /var/log/campfire/threads "$HOME/.campfire"
[[ -f "$HOME/AGENTS.md" ]] || cp /opt/campfire/defaults/AGENTS.md "$HOME/AGENTS.md"
[[ -f "$HOME/README.md" ]] || cp /opt/campfire/defaults/README.md "$HOME/README.md"

current="${CAMPFIRE_INITIAL_AGENT:-}"
if [[ -z "$current" ]] || ! participant_adapter "$current" >/dev/null 2>&1; then current="$(choose_first_available)"; fi
[[ -n "$current" ]] || { echo "Campfire: no enabled participants." >&2; exit 2; }

turn=1
while (( turn <= MAX_TURNS )); do
  adapter="$(participant_adapter "$current" || true)"
  [[ -n "$adapter" ]] || { current="$(choose_first_available "$current")"; [[ -n "$current" ]] || exit 3; continue; }

  handoff="$HOME/.campfire/handoff"; rm -f "$handoff"
  run_id="$(printf '%06d-%s' "$turn" "$current")"
  run_log="/var/log/campfire/runs/$run_id.log"
  thread_dir="/var/log/campfire/threads/$current"
  thread_file="$thread_dir/thread.txt"
  mkdir -p "$thread_dir"

  export CAMPFIRE_CURRENT_AGENT="$current" CAMPFIRE_HANDOFF="$handoff"
  log_event run.started run "$run_id" agent "$current"

  {
    printf '\n===== %s | %s | START =====\n' "$run_id" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >> "$thread_file"

  set +e
  timeout --signal=TERM --kill-after=15 "$TURN_TIMEOUT" "$adapter" 2>&1 | tee "$run_log" | tee -a "$thread_file"
  status=${PIPESTATUS[0]}
  set -e

  printf '===== %s | status=%s | END =====\n' "$run_id" "$status" >> "$thread_file"
  log_event run.finished run "$run_id" agent "$current" status "$status" thread "$thread_file"

  if (( status != 0 )) && looks_temporarily_unavailable "$run_log"; then
    log_event participant.unavailable agent "$current" reason temporary_provider_limit
    if [[ "$UNAVAILABLE_POLICY" == wait ]]; then
      log_event participant.waiting agent "$current" seconds "$WAIT_SECONDS"; sleep "$WAIT_SECONDS"; log_event participant.retry agent "$current"; continue
    fi
    [[ "$UNAVAILABLE_POLICY" == fallback ]] || exit "$status"
    next="$(choose_first_available "$current")"; [[ -n "$next" ]] || exit "$status"
    log_event routing.fallback requested "$current" executed "$next"; current="$next"; continue
  fi

  [[ -s "$handoff" ]] || { log_event handoff.missing run "$run_id" agent "$current"; exit 4; }
  target="$(handoff_target "$handoff")"
  archive="/var/log/campfire/handoffs/$run_id.txt"; cp "$handoff" "$archive"
  [[ -n "$target" ]] || { log_event handoff.invalid run "$run_id" reason missing_recipient; exit 5; }
  [[ "$target" != "$current" ]] || { log_event handoff.invalid run "$run_id" reason self_handoff; exit 6; }

  if ! is_available_name "$target"; then
    log_event handoff.unavailable run "$run_id" requested "$target"
    if [[ "$UNAVAILABLE_POLICY" == wait ]]; then
      log_event participant.waiting agent "$target" seconds "$WAIT_SECONDS"; sleep "$WAIT_SECONDS"; current="$target"; continue
    fi
    [[ "$UNAVAILABLE_POLICY" == fallback ]] || exit 7
    next="$(choose_first_available "$current")"; [[ -n "$next" ]] || exit 7
    log_event routing.fallback requested "$target" executed "$next"; target="$next"
  fi

  log_event handoff.accepted run "$run_id" from "$current" to "$target" archive "$archive"
  current="$target"; turn=$((turn + 1))
done

log_event experiment.finished reason max_turns turns "$MAX_TURNS"
