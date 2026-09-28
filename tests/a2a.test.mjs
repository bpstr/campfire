import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import http from "node:http";
import { once } from "node:events";
import { A2AClient, registerA2ATools } from "../mcp/a2a.mjs";

const makeTask = (state = "WORKING", extra = {}) => ({ id: "task-1", contextId: "ctx-1", status: { state: `TASK_STATE_${state}` }, ...extra });
async function fixture(t, options = {}) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "campfire-a2a-"));
  const requests = [], audit = [];
  let base;
  const server = http.createServer(async (req, res) => {
    let body = "";
    for await (const chunk of req) body += chunk;
    const data = body ? JSON.parse(body) : undefined;
    requests.push({ url: req.url, headers: req.headers, data });
    if (options.handle && await options.handle(req, res, data)) return;
    res.setHeader("Content-Type", "application/json");
    if (!data) {
      const card = { name: "Reviewer", version: "1.0.0", description: "Review supplied code", capabilities: {},
        defaultInputModes: ["text/plain"], defaultOutputModes: ["text/plain"], skills: [],
        supportedInterfaces: [{ url: `${base}/rpc`, protocolBinding: "JSONRPC", protocolVersion: "1.0", tenant: "team-a" }] };
      options.card?.(card);
      res.end(JSON.stringify(card));
    } else {
      const result = options.result ? options.result(data) : data.method === "SendMessage" ? { task: makeTask() } : makeTask(data.method === "CancelTask" ? "CANCELED" : "COMPLETED");
      const response = { jsonrpc: "2.0", id: data.id, result };
      options.envelope?.(response);
      res.end(JSON.stringify(response));
    }
  });
  server.listen(0, "127.0.0.1");
  await once(server, "listening");
  base = `http://127.0.0.1:${server.address().port}`;
  t.after(async () => {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
    fs.rmSync(dir, { recursive: true, force: true });
  });
  const file = path.join(dir, "agents.json");
  const registry = { reviewer: { cardUrl: `${base}/.well-known/agent-card.json` } };
  const save = () => fs.writeFileSync(file, JSON.stringify(registry));
  save();
  const env = { CAMPFIRE_COMMUNICATION_ENABLED: "true", CAMPFIRE_A2A_ENABLED: "true", CAMPFIRE_CURRENT_AGENT: "codex", CAMPFIRE_A2A_AGENTS_FILE: file };
  const client = new A2AClient({ env, record: entry => audit.push(entry) });
  return { client, env, requests, audit, registry, save, dir, base };
}

for (const override of [
  { CAMPFIRE_COMMUNICATION_ENABLED: "false" }, { CAMPFIRE_A2A_ENABLED: "false" }, { CAMPFIRE_ASSISTANT_MODE: "1" }
]) test(`gating prevents networking: ${JSON.stringify(override)}`, async t => {
  const f = await fixture(t); Object.assign(f.env, override);
  await assert.rejects(f.client.agents(), /disabled/);
  await assert.rejects(f.client.send("reviewer", "hello"), /disabled/);
  await assert.rejects(f.client.task("reviewer", "task-1"), /disabled/);
  assert.equal(f.requests.length, 0);
});

test("listing is local; discovery validates the advertised binding", async t => {
  const f = await fixture(t);
  assert.deepEqual(await f.client.agents(), { agents: ["reviewer"] });
  assert.equal(f.requests.length, 0);
  assert.equal((await f.client.agents("reviewer")).name, "Reviewer");
  assert.equal(f.requests[0].url, "/.well-known/agent-card.json");
  assert.equal(f.requests[0].headers["a2a-version"], "1.0");
});

test("sends standard nonblocking A2A 1.0 wire format and retains correlation", async t => {
  const f = await fixture(t);
  const result = await f.client.send("reviewer", "Review only the supplied diff.");
  assert.equal(result.task.status.state, "TASK_STATE_WORKING");
  const rpc = f.requests[1].data;
  assert.equal(rpc.method, "SendMessage");
  assert.equal(rpc.params.tenant, "team-a");
  assert.equal(rpc.params.message.role, "ROLE_USER");
  assert.deepEqual(rpc.params.message.parts, [{ text: "Review only the supplied diff." }]);
  assert.equal(rpc.params.configuration.returnImmediately, true);
  assert.equal(rpc.params.configuration.historyLength, 0);
  assert.equal(rpc.params.message.messageId, result.messageId);
  assert.equal("taskId" in rpc.params.message, false);
  assert.equal("contextId" in rpc.params.message, false);
  assert.equal(f.audit.at(-1).taskId, "task-1");
  assert.equal(JSON.stringify(f.audit).includes("supplied diff"), false);
});

test("get and cancel preserve IDs and report the actual server state", async t => {
  const f = await fixture(t);
  assert.equal((await f.client.task("reviewer", "task-1")).task.status.state, "TASK_STATE_COMPLETED");
  assert.equal((await f.client.task("reviewer", "task-1", "cancel")).task.status.state, "TASK_STATE_CANCELED");
  assert.deepEqual(f.requests.filter(r => r.data).map(r => [r.data.method, r.data.params.id]), [["GetTask", "task-1"], ["CancelTask", "task-1"]]);
});

test("input-required and auth-required are not completion; follow-ups reuse server IDs", async t => {
  const f = await fixture(t, { result: data => ({ task: makeTask(data.params.message.taskId ? "AUTH_REQUIRED" : "INPUT_REQUIRED") }) });
  assert.equal((await f.client.send("reviewer", "Review")).task.status.state, "TASK_STATE_INPUT_REQUIRED");
  const answer = await f.client.send("reviewer", "Include dependencies.", { taskId: "task-1", contextId: "ctx-1" });
  assert.equal(answer.task.status.state, "TASK_STATE_AUTH_REQUIRED");
  assert.equal(f.requests.at(-1).data.params.message.taskId, "task-1");
  assert.equal(f.requests.at(-1).data.params.message.contextId, "ctx-1");
});

test("accepts immediate messages and preserves structured artifacts without fetching URLs", async t => {
  const f = await fixture(t, { result: () => { return {
    task: makeTask("COMPLETED", { artifacts: [{ artifactId: "a-1", parts: [{ data: { findings: 2 } }, { url: "https://untrusted.example/result" }] }] })
  }; } });
  const result = await f.client.send("reviewer", "Review");
  assert.deepEqual(result.task.artifacts[0].parts[0].data, { findings: 2 });
  assert.equal(f.requests.length, 2);
  const other = await fixture(t, { result: () => ({ message: { messageId: "reply-1", role: "ROLE_AGENT", parts: [{ text: "Done" }] } }) });
  assert.equal((await other.client.send("reviewer", "Hi")).message.parts[0].text, "Done");
});

test("independent sends have distinct message IDs", async t => {
  const f = await fixture(t);
  const results = await Promise.all([f.client.send("reviewer", "First"), f.client.send("reviewer", "Second")]);
  assert.notEqual(results[0].messageId, results[1].messageId);
});

test("unknown and self targets cannot reach the network", async t => {
  const f = await fixture(t);
  await assert.rejects(f.client.send("missing", "hello"), /not configured/);
  f.registry.codex = f.registry.reviewer; f.save();
  await assert.rejects(f.client.send("codex", "hello"), /Self communication/);
  assert.equal(f.requests.length, 0);
});

for (const url of ["http://remote.example/card", "https://user:secret@example.com/card", "https://example.com/card?token=secret", "file:///etc/passwd"]) {
  test(`rejects unsafe registry URL: ${url.split(":")[0]}`, async t => {
    const f = await fixture(t); f.registry.reviewer.cardUrl = url; f.save();
    await assert.rejects(f.client.send("reviewer", "Hi"), /A2A requires/);
    assert.equal(f.requests.length, 0);
  });
}

test("cross-origin Agent Card RPC endpoints are rejected before sending credentials", async t => {
  const f = await fixture(t, { card: card => { card.supportedInterfaces[0].url = "https://elsewhere.example/rpc"; } });
  await assert.rejects(f.client.send("reviewer", "Hi"), /another origin/);
  assert.equal(f.requests.length, 1);
});

test("HTTP redirects are not followed", async t => {
  const f = await fixture(t, { handle: async (req, res) => {
    res.writeHead(302, { Location: "/different-card" }); res.end(); return true;
  } });
  await assert.rejects(f.client.agents("reviewer"), /transport failed/);
  assert.equal(f.requests.length, 1);
});

for (const mutate of [card => { card.supportedInterfaces[0].protocolVersion = "0.3"; }, card => { card.supportedInterfaces[0].protocolBinding = "GRPC"; }, card => { card.capabilities.extensions = [{ required: true }]; }]) {
  test("unsupported versions, bindings, and required extensions fail before SendMessage", async t => {
    const f = await fixture(t, { card: mutate });
    await assert.rejects(f.client.send("reviewer", "Hi"), /not advertise|required.*not supported/i);
    assert.equal(f.requests.length, 1);
  });
}

test("token file authentication stays out of returned errors and audit logs", async t => {
  const f = await fixture(t, { envelope: response => { delete response.result; response.error = { code: -32001, message: "super-secret-token" }; } });
  const token = path.join(f.dir, "token"); fs.writeFileSync(token, "super-secret-token\n");
  f.registry.reviewer.bearerTokenFile = token; f.save();
  await assert.rejects(f.client.send("reviewer", "Private prompt"), error => /-32001/.test(error.message) && !error.message.includes("super-secret-token"));
  assert.equal(f.requests[1].headers.authorization, "Bearer super-secret-token");
  assert.equal(JSON.stringify(f.audit).includes("super-secret-token"), false);
  assert.equal(JSON.stringify(f.audit).includes("Private prompt"), false);
});

test("timeout aborts transport without retrying or claiming cancellation", async t => {
  const f = await fixture(t, { handle: async (req, res, data) => !!data });
  f.env.CAMPFIRE_A2A_REQUEST_TIMEOUT_MS = "100";
  await assert.rejects(f.client.send("reviewer", "Long job"), /timed out; remote execution may still be running.*messageId=/);
  assert.equal(f.requests.filter(r => r.data).length, 1);
  assert.equal(f.requests.at(-1).data.method, "SendMessage");
});

for (const mutation of [r => { r.id = "wrong"; }, r => { r.error = { code: -1 }; }, r => { r.jsonrpc = "1.0"; }]) {
  test("rejects malformed/cross-request JSON-RPC envelopes", async t => {
    const f = await fixture(t, { envelope: mutation });
    await assert.rejects(f.client.send("reviewer", "Hi"), /envelope/);
  });
}

test("rejects invalid task states and mismatched requested task IDs", async t => {
  const f = await fixture(t, { result: () => ({ task: makeTask("INVENTED") }) });
  await assert.rejects(f.client.send("reviewer", "Hi"), /task response/);
  const other = await fixture(t);
  await assert.rejects(other.client.task("reviewer", "different"), /changed the requested task ID/);
});

test("bounds UTF-8 request bytes before networking", async t => {
  const f = await fixture(t);
  await assert.rejects(f.client.send("reviewer", "🧪".repeat(20000)), /Invalid message/);
  assert.equal(f.requests.length, 0);
});

test("bounds remote response bytes", async t => {
  const f = await fixture(t, { handle: async (req, res) => {
    res.setHeader("Content-Type", "application/json"); res.end(JSON.stringify({ text: "x".repeat(1024 * 1024) })); return true;
  } });
  await assert.rejects(f.client.agents("reviewer"), /exceeds 1 MiB/);
});

test("rejects malformed JSON, non-JSON bodies, and HTTP failures", async t => {
  for (const [status, type, body, pattern] of [[200, "application/json", "{", /Invalid A2A JSON/], [200, "text/html", "<p>no</p>", /not JSON/], [401, "application/json", "secret", /HTTP 401/]]) {
    const f = await fixture(t, { handle: async (req, res) => { res.writeHead(status, { "Content-Type": type }); res.end(body); return true; } });
    await assert.rejects(f.client.agents("reviewer"), pattern);
  }
});

test("validates registry size, schema, token files, and timeout settings", async t => {
  const f = await fixture(t);
  f.registry.reviewer.token = "not-allowed"; f.save();
  await assert.rejects(f.client.agents(), /Invalid A2A registry/);
  delete f.registry.reviewer.token; f.registry.reviewer.bearerTokenFile = "/nonexistent-campfire-token"; f.save();
  await assert.rejects(f.client.agents("reviewer"), /Cannot read A2A bearer token/);
  delete f.registry.reviewer.bearerTokenFile; f.save();
  f.env.CAMPFIRE_A2A_REQUEST_TIMEOUT_MS = "NaN";
  await assert.rejects(f.client.agents("reviewer"), /timeout must/);
  fs.writeFileSync(f.env.CAMPFIRE_A2A_AGENTS_FILE, " ".repeat(128 * 1024 + 1));
  await assert.rejects(f.client.agents(), /bounded JSON/);
  assert.equal(f.requests.length, 0);
});

// Test MCP handler registration without installing the SDK or invoking any CLI.
const z = { string: () => ({ optional() { return this; }, min() { return this; } }), enum: () => ({ default() { return this; } }) };
test("MCP advertises no A2A tools while disabled, and precisely three when enabled", async t => {
  const tools = new Map(), server = { tool: (name, description, schema, fn) => tools.set(name, fn) };
  registerA2ATools(server, z, { env: {} });
  assert.equal(tools.size, 0);
  const f = await fixture(t);
  registerA2ATools(server, z, { env: f.env });
  assert.deepEqual([...tools.keys()], ["a2a_agents", "a2a_send", "a2a_task"]);
  const response = await tools.get("a2a_send")({ agent: "reviewer", message: "Review" });
  assert.equal(JSON.parse(response.content[0].text).task.id, "task-1");
  f.env.CAMPFIRE_A2A_ENABLED = "false";
  assert.equal((await tools.get("a2a_task")({ agent: "reviewer", taskId: "task-1", action: "cancel" })).isError, true);
});

test("failed remote tasks are MCP errors, not successful completion", async t => {
  const f = await fixture(t, { result: () => ({ task: makeTask("FAILED") }) });
  let handler;
  registerA2ATools({ tool: (name, description, schema, fn) => { if (name === "a2a_send") handler = fn; } }, z, { env: f.env });
  const response = await handler({ agent: "reviewer", message: "Review" });
  assert.equal(response.isError, true);
  assert.equal(JSON.parse(response.content[0].text).task.status.state, "TASK_STATE_FAILED");
});


test("malformed Agent Cards fail cleanly before delegation", async t => {
  const f = await fixture(t, { card: card => { card.supportedInterfaces = [null]; } });
  await assert.rejects(f.client.send("reviewer", "Hi"), /does not advertise/);
  const other = await fixture(t, { card: card => { card.capabilities.extensions = "bad"; } });
  await assert.rejects(other.client.send("reviewer", "Hi"), /Invalid A2A extensions/);
});

test("timeouts cover slow response bodies, not just connection setup", async t => {
  const f = await fixture(t, { handle: async (req, res, data) => {
    if (!data) return false;
    res.writeHead(200, { "Content-Type": "application/json" }); res.write('{"jsonrpc":'); return true;
  } });
  f.env.CAMPFIRE_A2A_REQUEST_TIMEOUT_MS = "100";
  await assert.rejects(f.client.send("reviewer", "Slow body"), /timed out/);
  assert.equal(f.requests.filter(r => r.data).length, 1);
});
