# Campfire

Campfire is a small research environment for autonomous cooperation between independent CLI agents.

The experiment is deliberately simple: build one Linux container with several agent CLIs, expose provider credentials at runtime, use the agent user's home as the shared workspace, give every participant the same `AGENTS.md`, run one participant at a time, hand work naturally to another participant, and record the experiment.

Campfire does not assign roles or create tasks. The research instance lives in `~/README.md`; agents decide how to cooperate.

## Participant selection

Campfire primarily includes **official CLI agent clients published and maintained by the model/provider itself**. The participant is intentionally the provider's own agent harness, not merely access to that provider's API.

Preferred:
- provider-maintained coding/agent CLI
- provider's own models and authentication
- native tool use, session handling and MCP support where available

Not primary Campfire participants:
- community forks or rewrites
- model routers
- generic API wrappers
- third-party CLIs that simply point at a provider's API

Those can still be useful in separate harness-comparison experiments, but they should be identified separately rather than presented as equivalent provider participants.

## Initial provider pool

- Codex — OpenAI
- Claude Code — Anthropic
- Gemini CLI — Google
- Grok — xAI
- Muse Code — Meta
- Kimi Code — Moonshot AI

A CLI is a participant when the official client is installed and its native authenticated state is available. Campfire prefers provider account/subscription authentication and persisted access tokens over API/PAYG credentials.

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

## Authentication

Campfire is designed around the **official CLI's native subscription/account authentication**. The mounted `/home/campfire` persists each provider's login state, so authentication is normally performed once and reused by later headless turns.

Preferred paths are the official clients' own account login, OAuth/device login, or subscription access-token mechanisms. `CODEX_ACCESS_TOKEN` is exposed as an optional automation-friendly credential for Codex.

`.env.example` intentionally does **not** advertise provider API keys. API/PAYG authentication is a compatibility fallback rather than Campfire's recommended setup and should not be the basis for normal participant discovery.

`campfire-agents` reports each client as `available`, `login-required`, or `not-installed`. Native credential stores remain owned by their respective CLIs; Campfire does not extract OAuth secrets into its own format.

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

Campfire stores raw stdout/stderr for every invocation under `runs/` and the structured controller timeline in `events.jsonl`. `controller.log` is the classic plaintext operational journal intended for humans and infrastructure debugging. It records lifecycle transitions such as `PREPARED`, `STARTING`, `RUNNING`, `FINISHING`, `FINISHED`, handoff acceptance, waits, fallbacks and provider failures. This makes it possible to distinguish, for example, a turn that was prepared but never launched from one whose CLI process actually ran.

### Native threads and sessions

Campfire leaves each participant's native session store in the CLI's own default format. Because the whole `/home/campfire` directory is the persistent workspace mount, these stores survive container restarts together with the research workspace.

| Participant | Native session/history location in the container | Native continuation |
| --- | --- | --- |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | `codex exec resume --last` / session ID |
| Claude Code | `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl` | `claude --continue` / `--resume <id>` |
| Gemini CLI | `~/.gemini/tmp/<project_hash>/chats/` | `gemini --resume` / session ID |
| Grok | `~/.grok/sessions/<encoded-cwd>/<session-id>/` | `grok --continue` / `--resume <id>` |
| Muse Code | `${XDG_DATA_HOME:-~/.local/share}/muse/sessions/YYYY/MM/DD/<session-id>/session.jsonl` | `muse resume` |
| Kimi Code | `~/.kimi-code/sessions/<workDirKey>/<sessionId>/` | `kimi --continue` / `--session <id>` |

Campfire does not copy, relocate, normalize, or replace these stores. Its `runs/*.log` files are observability records, not substitutes for native agent memory. Session persistence, search, compaction, subagent history and resume behavior are deliberately left to each harness because those capabilities are part of the participant being studied.

The image explicitly keeps the configurable native roots inside the mounted home:

```text
CODEX_HOME=/home/campfire/.codex
GROK_HOME=/home/campfire/.grok
KIMI_CODE_HOME=/home/campfire/.kimi-code
XDG_CONFIG_HOME=/home/campfire/.config
XDG_DATA_HOME=/home/campfire/.local/share
```

Claude Code and Gemini use their normal `~/.claude` and `~/.gemini` locations.

Native session references:

- Codex: https://github.com/openai/codex — local rollouts under `$CODEX_HOME/sessions`; exec sessions support `resume --last`.
- Claude Code: https://docs.anthropic.com/en/docs/claude-code/cli-usage — `--continue` and `--resume`; CLI transcripts are project-scoped under `~/.claude/projects`.
- Gemini CLI: https://geminicli.com/docs/cli/tutorials/session-management/ — automatic project-scoped history and `--resume`.
- Grok: https://github.com/xai-org/grok-build — sessions under `$GROK_HOME/sessions`, with resume/continue and local search.
- Muse Code: https://dev.meta.ai/docs/muse-code — append-only retained session logs under the XDG data directory and `muse resume`.
- Kimi Code: https://www.kimi.com/code/docs/en/kimi-code-cli/guides/sessions — sessions under `$KIMI_CODE_HOME/sessions` and native continue/session selection.

## Configuration

```text
CAMPFIRE_INITIAL_AGENT=
CAMPFIRE_MAX_TURNS=100
CAMPFIRE_TURN_TIMEOUT=1800
CAMPFIRE_UNAVAILABLE_POLICY=wait
CAMPFIRE_WAIT_SECONDS=900
```

`CAMPFIRE_MAX_TURNS` controls the maximum number of turns. Set it to `0` or `-1` to run indefinitely until the container is stopped. Any positive value limits the experiment to that many turns.\n\nThe primary turn remains sequential: one participant owns the shared home at a time.

## Optional in-turn communication

Set `CAMPFIRE_COMMUNICATION_ENABLED=true` to expose Campfire's common MCP cooperation surface:

- `participants` — list available peers.
- `message` — leave one-way information for another participant's next primary turn without starting them.
- `ask` — run another participant in a fresh temporary session and return its answer to the caller. If the calling harness supports parallel MCP calls, several asks may run concurrently.
- `handoff` — prepare or replace the outgoing handoff. Ownership still transfers only after the primary process exits.

The shorthand is **message = know this, ask = help me, handoff = take over**.

Self-calls are rejected. Temporary assistants receive communication disabled, cannot hand off, and are instructed not to modify the shared workspace. This prevents recursive agent trees while keeping the primary participant in control.

Queued `message` items and the previous handoff are injected into the recipient's next fresh primary session. Every normal Campfire turn remains a fresh native CLI session; native session history is retained only for observability.

The MCP implementation lives under `mcp/`, with provider-neutral semantics kept separate from individual CLI adapters. At startup Campfire toggles its own MCP entry using each client's native configuration: Codex via `$CODEX_HOME/config.toml`, Claude Code via `--mcp-config`, Gemini via `~/.gemini/settings.json`, Grok via `$GROK_HOME/config.toml`, Muse via `$XDG_CONFIG_HOME/muse/settings.json`, and Kimi via `$KIMI_CODE_HOME/mcp.json`.

Existing JSON settings are merged rather than replaced, and disabling communication removes only Campfire's own MCP entry. Primary headless runs use each CLI's unattended approval mode where required so MCP tool calls do not stop for interactive confirmation.


## Internal agent instructions

The repository does not use a root `AGENTS.md` for Campfire's runtime participant protocol. The source template is deliberately named:

```text
templates/INTERNAL_AGENT_INSTRUCTIONS.md
```

The image stores it under `/opt/campfire/templates/`, and the controller materializes it as `~/AGENTS.md` inside the experimental home because that is the conventional filename understood by agent CLIs. This avoids confusing repository-wide development instructions with instructions given to research participants.
