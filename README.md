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

For the five-participant guestbook example, follow [the setup guide](research/SETUP.md) to prepare CLI logins in the persistent volume before starting the controller.

```bash
./setup.sh
```

The script prints each CLI's own browser link or device code, waits for you to complete its login, and saves credentials in `workspace/`. For a new workspace it also creates `workspace/.campfire/next`, whose first line selects the initial CLI. Gemini's login is part of its interactive CLI; run `./setup.sh --gemini-login` when ready for that step. The script does not start the experiment. Once the run is authorized and `.env` is configured, start the controller with:

```bash
docker run --rm \
  --hostname campfire \
  --env-file .env \
  -v "$(pwd)/workspace:/home/campfire" \
  -v "$(pwd)/logs:/var/log/campfire" \
  campfire
```

## Authentication

Campfire is designed around the **official CLI's native subscription/account authentication**. The mounted `/home/campfire` persists each provider's login state, so authentication is normally performed once and reused by later headless turns.

Preferred paths are the official clients' own account login, OAuth/device login, or subscription access-token mechanisms. If using `CODEX_ACCESS_TOKEN`, pass it to `codex login --with-access-token` during setup; setting the variable alone does not authenticate `codex exec`.

`.env.example` intentionally does **not** advertise provider API keys. API/PAYG authentication is a compatibility fallback rather than Campfire's recommended setup and should not be the basis for normal participant discovery.

`campfire-agents` reports each client as `available`, `login-required`, or `not-installed`. Native credential stores remain owned by their respective CLIs; Campfire does not extract OAuth secrets into its own format.

## Handoff model

A turn runs until the participant process exits. The controller reads `workspace/.campfire/next` and sends every byte after its first line as the selected CLI's prompt. The first line is only the recipient name. During the turn the participant writes or revises `$CAMPFIRE_HANDOFF` in the same format:

```text
gemini
Natural-language handoff message.
```

The handoff becomes effective only after process exit. The controller archives it and copies it to `.campfire/next` for the next turn or a later run. Self-handoffs and empty message bodies are rejected. Put standing behavior in `AGENTS.md`; the adapters add no instructions to the handoff text.

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
    ├── 000001-codex-<attempt-id>.log
    └── ...
```

Campfire stores each CLI's stdout/stderr under `runs/` and the structured controller timeline in `events.jsonl`. CLI output is human-readable by default. Gemini's normal output summarizes its live JSON event stream so you can see session start, tool activity, responses, errors, and periods without events. Set `CAMPFIRE_JSON_OUTPUT=true` in `.env` to request raw JSON event streams from Claude, Gemini, and Muse. `controller.log` is the classic plaintext operational journal intended for humans and infrastructure debugging. It records lifecycle transitions such as `PREPARED`, `STARTING`, `RUNNING`, `FINISHING`, `FINISHED`, handoff acceptance, waits, fallbacks and provider failures. This makes it possible to distinguish, for example, a turn that was prepared but never launched from one whose CLI process actually ran.

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
CAMPFIRE_MAX_TURNS=6
CAMPFIRE_TURN_TIMEOUT=1800
CAMPFIRE_UNAVAILABLE_POLICY=wait
CAMPFIRE_WAIT_SECONDS=900
```

The first line of `workspace/.campfire/next` selects the initial participant. `CAMPFIRE_MAX_TURNS` controls the maximum number of turns. Set it to `0` or `-1` to run indefinitely until the container is stopped. Any positive value limits the experiment to that many turns. The primary turn remains sequential: one participant owns the shared home at a time.

## Optional in-turn communication

Set `CAMPFIRE_COMMUNICATION_ENABLED=true` to expose Campfire's common MCP cooperation surface:

- `participants` — list available peers.
- `message` — leave one-way information for another participant's next primary turn without starting them.
- `ask` — run another participant in a fresh temporary session and return its answer to the caller. If the calling harness supports parallel MCP calls, several asks may run concurrently.
- `handoff` — prepare or replace the outgoing handoff. Ownership still transfers only after the primary process exits.

The shorthand is **message = know this, ask = help me, handoff = take over**.

Self-calls are rejected. Temporary assistants receive communication disabled, cannot hand off, and are instructed not to modify the shared workspace. This prevents recursive agent trees while keeping the primary participant in control.

Queued `message` items remain as files under `~/.campfire/inbox/<participant>/`, which `AGENTS.md` tells participants to inspect. The incoming handoff body is the complete prompt for the next fresh native CLI session; native session history is retained only for observability.

The MCP implementation lives under `mcp/`, with provider-neutral semantics kept separate from individual CLI adapters. At startup Campfire toggles its own MCP entry using each client's native configuration: Codex via `$CODEX_HOME/config.toml`, Claude Code via `--mcp-config`, Gemini via `~/.gemini/settings.json`, Grok via `$GROK_HOME/config.toml`, Muse via `$XDG_CONFIG_HOME/muse/settings.json`, and Kimi via `$KIMI_CODE_HOME/mcp.json`.

Existing JSON settings are merged rather than replaced, and disabling communication removes only Campfire's own MCP entry. Primary headless runs use each CLI's unattended approval mode where required so MCP tool calls do not stop for interactive confirmation.


## Internal agent instructions

The repository does not use a root `AGENTS.md` for Campfire's runtime participant protocol. The source template is deliberately named:

```text
templates/INTERNAL_AGENT_INSTRUCTIONS.md
```

The image stores it under `/opt/campfire/templates/`, and the controller materializes it as `~/AGENTS.md` inside the experimental home. `~/CLAUDE.md` and `~/GEMINI.md` are links to that same file so those CLIs load the shared rules. This avoids confusing repository-wide development instructions with instructions given to research participants.


## Roadmap

- [x] Shared persistent home with fresh sessions per turn
- [x] Six-turn guestbook smoke-test research instance
- [x] Natural-language handoffs with self-handoff protection
- [x] Wait/fallback/stop handling for temporary provider limits
- [x] Classic controller log, structured events and per-run output
- [x] Native CLI session/history preservation
- [x] Optional MCP `participants`, `message`, `ask` and `handoff`
- [x] Native subscription/account authentication as the preferred model
- [ ] Verify Docker image builds cleanly on a fresh host
- [ ] Verify unattended authenticated startup for every installed official CLI
- [ ] Run the six-provider guestbook test with communication disabled
- [ ] Run the same guestbook test with MCP communication enabled
- [ ] Validate concurrent `ask` calls and temporary-provider-limit recovery
