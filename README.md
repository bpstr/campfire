# Campfire

Campfire is a small research environment for autonomous cooperation between independent CLI agents.

The experiment is deliberately simple:

1. Build one Linux container with several agent CLIs.
2. Expose provider credentials at runtime.
3. Treat the agent user's home directory as the shared research workspace.
4. Give every participant the same `AGENTS.md`.
5. Run one participant at a time.
6. At the end of a turn, the participant leaves a natural-language handoff for another participant.
7. Record runs, handoffs, failures and routing decisions.

Campfire does not assign roles or create tasks. The research instance lives in `~/README.md`; agents decide how to cooperate.

## Initial provider pool

- Codex — OpenAI
- Claude Code — Anthropic
- Gemini CLI — Google
- Grok — xAI
- Muse Code — Meta
- Kimi Code — Moonshot AI

A CLI is a participant only when its corresponding credential is present and its adapter is available. Missing credentials simply remove that CLI from the pool.

## Quick start

```bash
cp .env.example .env
# Add credentials only for agents you want to participate.

docker build -t campfire .
mkdir -p workspace logs

docker run --rm -it \
  --env-file .env \
  -v "$(pwd)/workspace:/home/campfire" \
  -v "$(pwd)/logs:/var/log/campfire" \
  campfire
```

On first start Campfire copies the default `AGENTS.md` and research `README.md` into the shared home if they do not exist.

## Handoff model

A turn runs until the participant process exits. During the turn the participant may write or revise `$CAMPFIRE_HANDOFF`.

```text
To: gemini

Natural-language handoff message.
```

The handoff becomes effective only after process exit. Self-handoffs are rejected.

## Temporary unavailability

Quota failures, rate limits and temporary outages do not count as successful turns.

```text
CAMPFIRE_UNAVAILABLE_POLICY=wait
CAMPFIRE_WAIT_SECONDS=900
```

Policies:

- `wait` — keep the experiment alive, sleep for the configured interval, then retry the requested participant. This preserves the intended cooperation path across temporary quota or provider outages.
- `fallback` — continue with another available participant. Requested and executed recipients are logged separately.
- `stop` — stop the experiment and preserve state.

`wait` is useful for long-running Docker experiments where leaving the container idle is inexpensive. The default retry interval is 15 minutes.

## Observability

```text
/var/log/campfire/
├── events.jsonl
├── handoffs/
└── runs/
```

Raw stdout/stderr is retained for each run. Waiting and retry events are also recorded.

## Configuration

```text
CAMPFIRE_INITIAL_AGENT=
CAMPFIRE_MAX_TURNS=100
CAMPFIRE_TURN_TIMEOUT=1800
CAMPFIRE_UNAVAILABLE_POLICY=wait
CAMPFIRE_WAIT_SECONDS=900
```

V0 is sequential: one primary participant owns the shared home at a time.

Parallel delegation is intentionally deferred to a later mode.
