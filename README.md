# Campfire

Campfire is a small research environment for autonomous cooperation between independent CLI agents.

The experiment is deliberately simple: build one Linux container with several agent CLIs, expose provider credentials at runtime, use the agent user's home as the shared workspace, give every participant the same `AGENTS.md`, run one participant at a time, hand work naturally to another participant, and record the experiment.

Campfire does not assign roles or create tasks. The research instance lives in `~/README.md`; agents decide how to cooperate.

## Initial provider pool

- Codex — OpenAI
- Claude Code — Anthropic
- Gemini CLI — Google
- Grok — xAI
- Muse Code — Meta
- Kimi Code — Moonshot AI

A CLI is a participant only when its corresponding credential is present and its adapter is available.

## Quick start

```bash
cp .env.example .env
docker build -t campfire .
mkdir -p workspace logs

docker run --rm -it \
  --env-file .env \
  -v "$(pwd)/workspace:/home/campfire" \
  -v "$(pwd)/logs:/var/log/campfire" \
  campfire
```

## Handoff model

A turn runs until the participant process exits. During the turn the participant may write or revise `$CAMPFIRE_HANDOFF`.

```text
To: gemini

Natural-language handoff message.
```

The handoff becomes effective only after process exit. Self-handoffs are rejected.

## Temporary unavailability

```text
CAMPFIRE_UNAVAILABLE_POLICY=wait
CAMPFIRE_WAIT_SECONDS=900
```

Policies:

- `wait` — keep the experiment alive, sleep, then retry the requested participant.
- `fallback` — continue with another available participant.
- `stop` — stop and preserve state.

## Observability

```text
/var/log/campfire/
├── events.jsonl
├── handoffs/
└── runs/
    ├── 000001-codex.log
    └── ...
```

Campfire stores raw stdout/stderr for every invocation under `runs/` and the structured controller timeline in `events.jsonl`.

### Native threads and sessions

Campfire does not copy, relocate, normalize, or replace participant conversation history. Each CLI keeps its native threads, sessions, history, and indexes in its own default location and format.

Where a CLI supports native session continuation, history search, or conversation recall, the participant should be allowed to use that mechanism directly. Campfire's per-run logs are observability records, not substitutes for native agent memory.

This intentionally preserves differences between agent harnesses: session persistence and history capabilities are part of the participant being studied.

## Configuration

```text
CAMPFIRE_INITIAL_AGENT=
CAMPFIRE_MAX_TURNS=100
CAMPFIRE_TURN_TIMEOUT=1800
CAMPFIRE_UNAVAILABLE_POLICY=wait
CAMPFIRE_WAIT_SECONDS=900
```

`CAMPFIRE_MAX_TURNS` controls the maximum number of turns. Set it to `0` or `-1` to run indefinitely until the container is stopped. Any positive value limits the experiment to that many turns.\n\nV0 is sequential: one primary participant owns the shared home at a time. Parallel delegation is intentionally deferred.
