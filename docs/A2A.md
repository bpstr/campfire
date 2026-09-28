# Outbound A2A delegation

Campfire can call separately deployed remote agents through **A2A 1.0 JSON-RPC**, using three optional tools on its existing MCP server. The native CLIs remain unchanged. This is an outbound client, not an A2A server, and it does not turn local CLIs into network services.

```text
Local CLI -> Campfire MCP -> A2A SendMessage -> remote specialist
Local CLI <- Campfire MCP <- task/message/artifacts <- remote specialist
```

Local `participants`, `message`, `ask`, and `handoff` retain their existing behavior. Remote agents are deliberately separate from local participants: A2A completion cannot select the next primary CLI or transfer ownership of the shared home. Independent outbound calls may overlap; local primary turns remain sequential.

## Enable

Rebuild the image after updating the repository:

```bash
docker build -t campfire .
cp mcp/a2a-agents.example.json a2a-agents.json
```

Edit `a2a-agents.json` to name the remote services you explicitly trust. The example URL is a placeholder, not a running service. Each service must actually expose an A2A 1.0 Agent Card and JSON-RPC endpoint. A native CLI alone is not such an endpoint.

```json
{
  "reviewer": {
    "cardUrl": "https://reviewer.example/.well-known/agent-card.json",
    "bearerTokenFile": "/run/secrets/a2a-reviewer-token"
  }
}
```

Use unique remote aliases, not the current local CLI's name. `cardUrl` is the full Agent Card URL, so nonstandard discovery paths are supported. Omit `bearerTokenFile` for an intentionally unauthenticated agent; otherwise provide an absolute path to a file containing its bearer token. Never put a token directly into the registry or URL.

Set in `.env`:

```dotenv
CAMPFIRE_COMMUNICATION_ENABLED=true
CAMPFIRE_A2A_ENABLED=true
CAMPFIRE_A2A_AGENTS_FILE=/etc/campfire/a2a-agents.json
CAMPFIRE_A2A_REQUEST_TIMEOUT_MS=30000
```

Both flags are required. With either disabled, the extra tools are not advertised and no A2A registry or network access is attempted. Local temporary assistants cannot use A2A even if the A2A flag remains enabled.

Mount configuration and credentials read-only, **outside the shared home**:

```bash
docker run --rm \
  --hostname campfire \
  --env-file .env \
  -v "$(pwd)/workspace:/home/campfire" \
  -v "$(pwd)/logs:/var/log/campfire" \
  -v "$(pwd)/a2a-agents.json:/etc/campfire/a2a-agents.json:ro" \
  -v "/absolute/private/path/reviewer-token:/run/secrets/a2a-reviewer-token:ro" \
  campfire
```

Create the token file outside this repository and grant read access only as needed for the container's `campfire` user. Remove the secret mount when using an unauthenticated endpoint. Do not commit credentials. The local registry filename is gitignored.

Codex's provider template explicitly forwards Campfire runtime controls with `env_vars`. For custom CLI/MCP launchers, forward the same controls rather than hardcoding `CAMPFIRE_COMMUNICATION_ENABLED=true`, which would bypass the local temporary-assistant restriction. Bearer tokens are read from files, not copied into native MCP settings. Ensure the client's tool timeout exceeds two HTTP request timeouts plus overhead, since a task operation first discovers the Agent Card.

Existing persistent `~/AGENTS.md` files are not overwritten on startup. Merge the new A2A guidance from `templates/INTERNAL_AGENT_INSTRUCTIONS.md` into an existing workspace's instructions when needed; preserve any experiment-specific rules.

## Tool examples

The following are MCP tool arguments, not raw A2A wire messages:

```text
a2a_agents({})
-> {"agents":["reviewer"]}

a2a_agents({"agent":"reviewer"})
-> the remote Agent Card and its skills

a2a_send({"agent":"reviewer","message":"Review this supplied diff for races: ..."})
-> {"agent":"reviewer","messageId":"...","task":{
     "id":"task-42","contextId":"ctx-7",
     "status":{"state":"TASK_STATE_WORKING"}}}

a2a_task({"agent":"reviewer","taskId":"task-42","action":"get"})
-> current task state, status message, and artifacts

a2a_send({"agent":"reviewer","taskId":"task-42","contextId":"ctx-7",
          "message":"Include the retry path too."})
-> continuation of the same task, for example after INPUT_REQUIRED

a2a_task({"agent":"reviewer","taskId":"task-42","action":"cancel"})
-> the server's actual task state; not an assumed cancellation
```

`SendMessage` uses `returnImmediately: true`. A response may be an immediate agent message, a completed task, or unfinished work. `WORKING`/`SUBMITTED` are not completion; `INPUT_REQUIRED` needs a reply and `AUTH_REQUIRED` needs operator-managed authorization. Failed/rejected tasks are returned as MCP errors with their task data retained. A cancellation request is not proof of cancellation unless the returned state confirms it.

Preserve the remote alias, task ID, and context ID in the normal handoff when work spans primary turns. Later participants can inspect the task without resubmitting it. There is no automatic polling loop or local task database: the remote agent owns task persistence and retention. Do useful independent work between status checks.

A timeout or broken connection **does not cancel remote execution**. Campfire never automatically retries or silently falls back to a local CLI. If a task ID is known, retrieve it. If the initial send lost its response before returning a task ID, use the returned/logged message ID to reconcile with the remote operator; do not assume resubmission is idempotent. A2A has no universally safe way for this client to infer a lost task ID.

## Boundaries

Only allowlisted, host-configured names are callable; tools never accept arbitrary URLs or shell commands. Card-advertised RPC URLs must have exactly the same origin as the configured card. Redirects are disabled, including redirects to a different path on the same origin. HTTPS is required except for explicit loopback HTTP development endpoints. Inside Docker, loopback refers to the container, not the host.

The client sends only the explicit message and protocol fields, never an automatic workspace snapshot or native CLI credentials. Artifacts, including structured data and file URLs, are returned as data; they are not fetched, written to disk, or executed. Remote cards/results are untrusted content. Validate any proposed change before applying it locally.

Credentials are bearer-token files read on demand; OAuth login/refresh, API-key headers, mutual TLS setup, and Agent Card signature verification are not implemented. Configure only trusted service identities/origins. Read-only mounts protect configuration from ordinary in-container edits, but this is not a hostile-agent sandbox: local CLIs share a user and may be able to read mounted credentials. Use OS/network isolation and restricted service credentials for stronger boundaries. Remote services can have their own costs, tools, or delegation; Campfire cannot enforce their internal budgets or prevent remote recursion.

Each request has a timeout (1..300000 ms, default 30000), a 64 KiB encoded request limit, and a 1 MiB response limit. The registry is limited to 128 KiB and 100 aliases; token files to 8 KiB. No unbounded in-memory conversation history is accumulated. Status requests ask for zero history messages. Avoid large inline artifacts; this initial client rejects oversized responses rather than silently truncating them.

Communication logs contain operation, agent, request/message/task IDs, and task states, **not outbound prompts, HTTP headers, or bearer tokens**. Native CLI transcripts can still contain tool results and supplied messages under the existing session-retention behavior. Audit errors are reported to stderr without hiding an accepted task's response.

## Compatibility and verification

This first implementation supports **A2A 1.0 JSON-RPC only**: Agent Card discovery, `SendMessage`, `GetTask`, and `CancelTask`, including tenant routing and multi-turn task IDs. It sends `A2A-Version: 1.0`. Legacy 0.3 cards/bindings and required extensions are rejected explicitly. No streaming, push notifications, task listing, inbound A2A server, or controller handoff over A2A is implemented. This is a deliberately bounded client subset, not a claim of full protocol conformance.

Run without provider accounts or new dependencies, using Node 22:

```bash
node --test tests/a2a.test.mjs
```

Tests use a local HTTP fixture and exercise wire messages, lifecycle states, follow-ups, parallel correlation IDs, authorization headers, feature/assistant gates, timeouts, redirects, malformed responses, limits, and MCP handler registration. They do not invoke real model providers. The MCP handler tests use a registration stub; a full SDK/CLI integration run, Docker build, and interoperability against an independently implemented remote agent remain deployment checks.

Protocol sources checked 2026-09-28:

- [A2A specification](https://a2a-protocol.org/latest/specification/) — Agent Cards, JSON-RPC binding, messages, task states, version headers, and tenant routing.
- [A2A task lifecycle](https://a2a-protocol.org/latest/topics/life-of-a-task/) — task continuation and terminal/interrupted states.
- [Codex MCP configuration](https://developers.openai.com/codex/mcp/) — explicit stdio environment forwarding.
