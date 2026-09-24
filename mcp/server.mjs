#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

const enabled = /^(1|true|yes|on)$/i.test(process.env.CAMPFIRE_COMMUNICATION_ENABLED || "");
const current = process.env.CAMPFIRE_CURRENT_AGENT || "";
const root = process.env.CAMPFIRE_STATE_DIR || path.join(process.env.HOME || "/home/campfire", ".campfire");
const inboxRoot = path.join(root, "inbox");
const handoff = process.env.CAMPFIRE_HANDOFF || path.join(root, "handoff");
const runId = process.env.CAMPFIRE_RUN_ID || "unknown";
const askTimeout = Number(process.env.CAMPFIRE_ASK_TIMEOUT || "1800");

function requireEnabled() {
  if (!enabled) throw new Error("Campfire communication is disabled.");
}
function participants() {
  const r = spawnSync("campfire-agents", [], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr || "Unable to list participants.");
  return r.stdout.trim();
}
function assertTarget(target) {
  requireEnabled();
  if (target === current) throw new Error("Self communication is forbidden.");
  const available = participants().split(/\n/).map(x => x.trim().split(/\s+/)[0]).filter(Boolean);
  if (!available.includes(target)) throw new Error(`Participant is not currently available: ${target}`);
}
function appendEvent(type, target, extra = "") {
  fs.mkdirSync(root, { recursive: true });
  fs.appendFileSync(path.join(root, "communication.log"),
    `${new Date().toISOString()} [${type}] run=${runId} from=${current} to=${target}${extra ? " " + extra : ""}\n`);
}

const server = new McpServer({ name: "campfire", version: "0.1.0" });

server.tool("participants", "List Campfire participants available for communication.", {}, async () => {
  requireEnabled();
  return { content: [{ type: "text", text: participants() }] };
});

server.tool("message", "Leave a one-way message for another participant. It is delivered with their next primary turn and does not start them.", {
  participant: z.string(),
  message: z.string().min(1)
}, async ({ participant, message }) => {
  assertTarget(participant);
  const dir = path.join(inboxRoot, participant);
  fs.mkdirSync(dir, { recursive: true });
  const file = path.join(dir, `${Date.now()}-${runId}-${current}.txt`);
  fs.writeFileSync(file, `From: ${current}\nRun: ${runId}\n\n${message}\n`);
  appendEvent("MESSAGE", participant);
  return { content: [{ type: "text", text: `Message queued for ${participant}.` }] };
});

server.tool("handoff", "Set or replace the outgoing handoff. It becomes effective only when the current primary turn exits.", {
  participant: z.string(),
  message: z.string().min(1)
}, async ({ participant, message }) => {
  assertTarget(participant);
  fs.mkdirSync(path.dirname(handoff), { recursive: true });
  fs.writeFileSync(handoff, `To: ${participant}\n\n${message}\n`);
  appendEvent("HANDOFF", participant);
  return { content: [{ type: "text", text: `Handoff prepared for ${participant}; it will take effect when this turn exits.` }] };
});

server.tool("ask", "Ask another participant to work in a fresh temporary session and return its answer. The assistant cannot hand off or recursively communicate.", {
  participant: z.string(),
  message: z.string().min(1)
}, async ({ participant, message }) => {
  assertTarget(participant);
  appendEvent("ASK", participant, "state=STARTING");
  const r = spawnSync("/usr/local/bin/campfire-assist", [participant, message], {
    encoding: "utf8",
    timeout: askTimeout * 1000,
    env: { ...process.env, CAMPFIRE_COMMUNICATION_ENABLED: "false", CAMPFIRE_ASSISTANT_MODE: "1" }
  });
  appendEvent("ASK", participant, `state=FINISHED exit=${r.status ?? -1}`);
  if (r.error) throw r.error;
  if (r.status !== 0) throw new Error(r.stderr || `Assistant exited ${r.status}`);
  return { content: [{ type: "text", text: r.stdout }] };
});

await server.connect(new StdioServerTransport());
