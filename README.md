# Campfire

Campfire is a small research environment for autonomous cooperation between independent CLI agents.

The core experiment is deliberately simple:

1. Build one Linux container with several agent CLIs preinstalled.
2. Expose provider credentials at runtime.
3. Treat the agent user's home directory as the shared research workspace.
4. Give every participant the same `AGENTS.md`.
5. Run one participant at a time.
6. At the end of a turn, the participant leaves a natural-language handoff for another participant.
7. Record runs, handoffs, failures and routing decisions for later analysis.

Campfire does not assign roles or create tasks. The research instance lives in `~/README.md`; agents decide how to cooperate.

## Participants

The initial pool targets distinct providers:

- Codex — OpenAI
- Claude Code — Anthropic
- Gemini CLI — Google
- Grok — xAI
- Muse Code — Meta
- Kimi Code — Moonshot AI

A CLI is a participant only when its credential environment variable is present. Missing credentials simply remove that CLI from the pool.

## Quick start

```bash
cp .env.example .env
# Add only credentials for agents you want to participate.

docker build -t campfire .

mkdir -p workspace logs

docker run --rm -it \
  --env-file .env \
  -v "$(pwd)/workspace:/home/campfire" \
  -v "$(pwd)/logs:/var/log/campfire" \
  campfire
```

On first start Campfire copies the default `AGENTS.md` and research `README.md` into the shared home directory if they do not already exist.

## Research instance

Edit `workspace/README.md` to define the experiment.

Example:

```markdown
# Research instance

Invent useful software.

Explore ideas, investigate opportunities, build things, test them, challenge weak directions and improve promising ones.

There is no predetermined final deliverable.
```

## Handoffs

A turn runs until the participant process exits.

During the turn the participant may write or revise:

```text
$CAMPFIRE_HANDOFF
```

The handoff becomes effective only after the participant exits.

Format:

```text
To: gemini

Natural-language handoff message.
```

Self-handoffs are rejected. The recipient must be another currently available participant.

## Temporary unavailability

Provider quota failures, rate limits and temporary outages do not count as successful turns.

```text
CAMPFIRE_UNAVAILABLE_POLICY=fallback
```

Supported initial policies:

- `fallback` — continue with another available participant.
- `stop` — stop the experiment and preserve state.

The requested recipient remains in the logs even when fallback occurs.

## Observability

Campfire stores controller-owned logs outside the shared home:

```text
/var/log/campfire/
├── events.jsonl
├── handoffs/
└── runs/
```

Raw stdout/stderr is retained for every run.

## Configuration

```text
CAMPFIRE_INITIAL_AGENT=
CAMPFIRE_MAX_TURNS=100
CAMPFIRE_TURN_TIMEOUT=1800
CAMPFIRE_UNAVAILABLE_POLICY=fallback
```

V0 is sequential: exactly one primary participant owns the workspace at a time.

Parallel delegation is intentionally deferred to a later mode.
