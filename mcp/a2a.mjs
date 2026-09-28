// A deliberately small outbound A2A 1.0 JSON-RPC client. No listener, CLI
// replacement, workspace upload, implicit retries, or automatic artifact fetches.
import fs from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";

const truthy = value => /^(1|true|yes|on)$/i.test(value || "");
const object = value => value !== null && typeof value === "object" && !Array.isArray(value);
const own = (value, key) => Object.hasOwn(value, key);
const states = new Set(["SUBMITTED", "WORKING", "INPUT_REQUIRED", "AUTH_REQUIRED", "COMPLETED", "FAILED", "CANCELED", "REJECTED"].map(x => `TASK_STATE_${x}`));
const MAX_BYTES = 1024 * 1024;

function text(value, name, max = 1024) {
  if (typeof value !== "string" || !value.trim() || Buffer.byteLength(value) > max) {
    throw new Error(`Invalid ${name}.`);
  }
  return value;
}

function readBounded(filename, limit) {
  if (typeof filename !== "string" || !path.isAbsolute(filename)) throw new Error("A2A file paths must be absolute.");
  const fd = fs.openSync(filename, "r");
  try {
    if (!fs.fstatSync(fd).isFile()) throw new Error("A2A configuration and token paths must be regular files.");
    const buffer = Buffer.alloc(limit + 1);
    let size = 0, count;
    while (size < buffer.length && (count = fs.readSync(fd, buffer, size, buffer.length - size, null)) > 0) size += count;
    if (size > limit) throw new Error("A2A file exceeds its size limit.");
    return buffer.subarray(0, size).toString("utf8");
  } finally { fs.closeSync(fd); }
}

function endpoint(value) {
  let url;
  try { url = new URL(value); } catch { throw new Error("Invalid A2A URL."); }
  const loopback = ["127.0.0.1", "[::1]", "localhost"].includes(url.hostname);
  if (url.username || url.password || url.search || url.hash ||
      (url.protocol !== "https:" && !(url.protocol === "http:" && loopback))) {
    throw new Error("A2A requires HTTPS (HTTP is allowed only on loopback), without URL credentials, queries, or fragments.");
  }
  return url;
}

function validateTask(task) {
  if (!object(task) || !states.has(task.status?.state)) throw new Error("Invalid A2A 1.0 task response.");
  text(task.id, "task ID");
  text(task.contextId, "context ID");
  return task;
}

export class A2AClient {
  constructor({ env = process.env, fetchImpl = globalThis.fetch, record = () => {} } = {}) {
    this.env = env;
    this.fetch = fetchImpl;
    this.record = record;
  }

  requireEnabled() {
    if (!truthy(this.env.CAMPFIRE_COMMUNICATION_ENABLED) || !truthy(this.env.CAMPFIRE_A2A_ENABLED) ||
        truthy(this.env.CAMPFIRE_ASSISTANT_MODE)) {
      throw new Error("A2A communication is disabled for this session.");
    }
  }

  registry() {
    this.requireEnabled();
    let entries;
    try { entries = JSON.parse(readBounded(this.env.CAMPFIRE_A2A_AGENTS_FILE || "/etc/campfire/a2a-agents.json", 128 * 1024)); }
    catch { throw new Error("Cannot read A2A registry; provide a valid, bounded JSON file using an absolute path."); }
    if (!object(entries) || Object.keys(entries).length > 100) throw new Error("A2A registry must contain at most 100 named agents.");
    for (const [name, entry] of Object.entries(entries)) {
      if (!/^[a-z][a-z0-9_-]{0,63}$/.test(name) || !object(entry) ||
          Object.keys(entry).some(key => !["cardUrl", "bearerTokenFile"].includes(key))) {
        throw new Error("Invalid A2A registry entry; use a named agent with cardUrl and optional bearerTokenFile.");
      }
      endpoint(entry.cardUrl);
      if (entry.bearerTokenFile !== undefined && (typeof entry.bearerTokenFile !== "string" || !path.isAbsolute(entry.bearerTokenFile))) {
        throw new Error("A2A bearerTokenFile must be an absolute path.");
      }
    }
    return entries;
  }

  entry(agent) {
    const entries = this.registry();
    if (agent === this.env.CAMPFIRE_CURRENT_AGENT) throw new Error("Self communication is forbidden.");
    if (!own(entries, agent)) throw new Error("A2A agent is not configured.");
    return entries[agent];
  }

  audit(operation, agent, details = {}) {
    // Audit failures must not hide an already accepted remote task's ID.
    try { this.record({ operation, agent, ...details }); }
    catch { console.error("Campfire A2A audit write failed."); }
  }

  async request(url, entry, body) {
    const timeout = Number(this.env.CAMPFIRE_A2A_REQUEST_TIMEOUT_MS || 30000);
    if (!Number.isInteger(timeout) || timeout < 1 || timeout > 300000) throw new Error("A2A request timeout must be 1..300000 milliseconds.");
    const headers = { Accept: "application/json", "A2A-Version": "1.0" };
    if (entry.bearerTokenFile) {
      let token;
      try { token = readBounded(entry.bearerTokenFile, 8192).trim(); }
      catch { throw new Error("Cannot read A2A bearer token file."); }
      if (!/^[A-Za-z0-9._~+\/-]+=*$/.test(token)) throw new Error("Invalid A2A bearer token.");
      headers.Authorization = `Bearer ${token}`;
    }
    const encoded = body === undefined ? undefined : JSON.stringify(body);
    if (encoded && Buffer.byteLength(encoded) > 65536) throw new Error("A2A request exceeds 64 KiB.");
    if (encoded) headers["Content-Type"] = "application/json";
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      const response = await this.fetch(url, {
        method: encoded ? "POST" : "GET", headers, body: encoded,
        redirect: "error", signal: controller.signal
      });
      if (!response.ok) {
        await response.body?.cancel();
        throw new Error(`A2A HTTP ${response.status}.`);
      }
      const type = (response.headers.get("content-type") || "").split(";")[0].trim().toLowerCase();
      if (!["application/json", "application/a2a+json"].includes(type)) {
        await response.body?.cancel();
        throw new Error("A2A response is not JSON.");
      }
      if (!response.body) throw new Error("Empty A2A response.");
      const reader = response.body.getReader();
      let size = 0;
      const buffer = Buffer.alloc(MAX_BYTES);
      try {
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          size += value.byteLength;
          if (size > MAX_BYTES) throw new Error("A2A response exceeds 1 MiB.");
          buffer.set(value, size - value.byteLength);
        }
      } finally {
        await reader.cancel().catch(() => {});
        reader.releaseLock();
      }
      try { return JSON.parse(buffer.subarray(0, size).toString("utf8")); }
      catch { throw new Error("Invalid A2A JSON response."); }
    } catch (error) {
      if (controller.signal.aborted) throw new Error("A2A request timed out; remote execution may still be running. No retry was attempted.");
      if (error.message?.startsWith("A2A ") || error.message === "Invalid A2A JSON response." || error.message === "Empty A2A response.") throw error;
      // Do not expose transport errors, remote error bodies, or credentials.
      throw new Error("A2A transport failed; remote execution may still be running. No retry was attempted.");
    } finally { clearTimeout(timer); }
  }

  async discover(agent) {
    const entry = this.entry(agent);
    const url = endpoint(entry.cardUrl);
    const card = await this.request(url, entry);
    if (!object(card) || !Array.isArray(card.supportedInterfaces)) throw new Error("Agent must advertise an A2A 1.0 Agent Card.");
    const extensions = card.capabilities?.extensions;
    if (extensions !== undefined && (!Array.isArray(extensions) || extensions.some(extension => !object(extension)))) throw new Error("Invalid A2A extensions.");
    if (extensions?.some(extension => extension.required)) throw new Error("Required A2A extensions are not supported.");
    const selected = card.supportedInterfaces.find(item => object(item) && item.protocolBinding === "JSONRPC" && item.protocolVersion === "1.0");
    if (!selected) throw new Error("Agent does not advertise A2A 1.0 JSONRPC; no legacy fallback is attempted.");
    const rpcUrl = endpoint(selected.url);
    if (rpcUrl.origin !== url.origin) throw new Error("A2A Agent Card cannot redirect RPC requests or credentials to another origin.");
    if (selected.tenant !== undefined) text(selected.tenant, "tenant");
    return { entry, card, rpcUrl, tenant: selected.tenant };
  }

  async agents(agent) {
    if (agent !== undefined) return (await this.discover(agent)).card;
    return { agents: Object.keys(this.registry()).filter(name => name !== this.env.CAMPFIRE_CURRENT_AGENT).sort() };
  }

  async rpc(agent, method, params) {
    const { entry, rpcUrl, tenant } = await this.discover(agent);
    const id = randomUUID();
    this.audit(method, agent, { requestId: id, phase: "sending", ...(params.message ? { messageId: params.message.messageId } : { taskId: params.id }) });
    const response = await this.request(rpcUrl, entry, {
      jsonrpc: "2.0", id, method, params: { ...params, ...(tenant !== undefined ? { tenant } : {}) }
    });
    if (!object(response) || response.jsonrpc !== "2.0" || response.id !== id || own(response, "result") === own(response, "error")) {
      throw new Error("Invalid A2A JSON-RPC envelope.");
    }
    if (own(response, "error")) {
      const code = Number.isInteger(response.error?.code) ? response.error.code : "unknown";
      throw new Error(`A2A JSON-RPC error ${code}.`);
    }
    return response.result;
  }

  async send(agent, message, { taskId, contextId } = {}) {
    this.requireEnabled();
    text(message, "message", 64000);
    if (taskId !== undefined) text(taskId, "task ID");
    if (contextId !== undefined) text(contextId, "context ID");
    const messageId = randomUUID();
    let result;
    try {
      result = await this.rpc(agent, "SendMessage", {
        message: { messageId, role: "ROLE_USER", parts: [{ text: message }],
          ...(taskId !== undefined ? { taskId } : {}), ...(contextId !== undefined ? { contextId } : {}) },
        configuration: { returnImmediately: true, historyLength: 0, acceptedOutputModes: ["text/plain", "application/json"] }
      });
    } catch (error) {
      // A timeout is not proof of failure/cancellation; keep correlation data.
      throw new Error(`${error.message} messageId=${messageId}${taskId ? ` taskId=${JSON.stringify(taskId)}` : ""}`);
    }
    if (!object(result) || own(result, "task") === own(result, "message")) throw new Error("Invalid A2A SendMessage result.");
    if (own(result, "task")) {
      validateTask(result.task);
      if (taskId && result.task.id !== taskId) throw new Error("A2A response changed the requested task ID.");
      if (contextId && result.task.contextId !== contextId) throw new Error("A2A response changed the requested context ID.");
      this.audit("SendMessage", agent, { messageId, taskId: result.task.id, state: result.task.status.state });
    } else {
      if (!object(result.message) || result.message.role !== "ROLE_AGENT" || !Array.isArray(result.message.parts) || !result.message.parts.length) {
        throw new Error("Invalid A2A agent message.");
      }
      text(result.message.messageId, "response message ID");
      this.audit("SendMessage", agent, { messageId, phase: "message-received" });
    }
    return { agent, messageId, ...result };
  }

  async task(agent, taskId, action = "get") {
    this.requireEnabled();
    text(taskId, "task ID");
    if (!["get", "cancel"].includes(action)) throw new Error("Invalid A2A task action.");
    const method = action === "get" ? "GetTask" : "CancelTask";
    const task = validateTask(await this.rpc(agent, method, { id: taskId, ...(action === "get" ? { historyLength: 0 } : {}) }));
    if (task.id !== taskId) throw new Error("A2A response changed the requested task ID.");
    this.audit(method, agent, { taskId, state: task.status.state });
    return { agent, task };
  }
}

export function registerA2ATools(server, z, options = {}) {
  const client = new A2AClient(options);
  // No additional tools are advertised until both opt-in flags are enabled.
  try { client.requireEnabled(); } catch { return; }
  const respond = handler => async args => {
    try {
      const value = await handler(args);
      const failed = ["TASK_STATE_FAILED", "TASK_STATE_REJECTED"].includes(value.task?.status?.state);
      return { content: [{ type: "text", text: JSON.stringify(value) }], ...(failed ? { isError: true } : {}) };
    } catch (error) {
      return { isError: true, content: [{ type: "text", text: error.message }] };
    }
  };
  server.tool("a2a_agents", "List configured remote A2A agents, or inspect one Agent Card. These are not local handoff recipients.", {
    agent: z.string().optional()
  }, respond(({ agent }) => client.agents(agent)));
  server.tool("a2a_send", "Delegate to a remote agent or reply on an existing task. Returns its current state, not necessarily completion. Only the supplied message is sent; no shared workspace access.", {
    agent: z.string(), message: z.string().min(1), taskId: z.string().optional(), contextId: z.string().optional()
  }, respond(({ agent, message, taskId, contextId }) => client.send(agent, message, { taskId, contextId })));
  server.tool("a2a_task", "Get a remote task's current state/artifacts or request cancellation. Cancellation is confirmed only by the returned state; do not blindly resubmit timed-out work.", {
    agent: z.string(), taskId: z.string(), action: z.enum(["get", "cancel"]).default("get")
  }, respond(({ agent, taskId, action }) => client.task(agent, taskId, action)));
}
