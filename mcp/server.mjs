#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import fs from "node:fs";
import path from "node:path";
import { spawn, spawnSync } from "node:child_process";

const enabled = /^(1|true|yes|on)$/i.test(process.env.CAMPFIRE_COMMUNICATION_ENABLED || "");
const current = process.env.CAMPFIRE_CURRENT_AGENT || "";
const stateRoot = process.env.CAMPFIRE_STATE_DIR || path.join(process.env.HOME || "/home/campfire", ".campfire");
const inboxRoot = path.join(stateRoot, "inbox");
const handoff = process.env.CAMPFIRE_HANDOFF || path.join(stateRoot, "handoff");
const runId = process.env.CAMPFIRE_RUN_ID || "unknown";
const askTimeout = Number(process.env.CAMPFIRE_ASK_TIMEOUT || "1800");
const communicationLog = "/var/log/campfire/communication.log";

function requireEnabled() {
  if (!enabled) throw new Error("Campfire communication is disabled.");
}
function participantNames() {
  const r = spawnSync("campfire-agents", [], { encoding: "utf8" });
  if (r.status !== 0) throw new Error(r.stderr || "Unable to list participants.");
  return r.stdout.trim().split(/\n/).map(x => x.trim().split(/\s+/)[0]).filter(Boolean);
}
function assertTarget(target) {
  requireEnabled();
  if (target === current) throw new Error("Self communication is forbidden.");
  if (!participantNames().includes(target)) throw new Error(`Participant is not currently available: ${target}`);
}
function log(type, target, extra = "") {
  fs.appendFileSync(communicationLog,
    `${new Date().toISOString()} [${type}] run=${runId} from=${current} to=${target}${extra ? " " + extra : ""}\n`);
}
function runAssistant(participant, message) {
  return new Promise((resolve, reject) => {
    const child = spawn("/usr/local/bin/campfire-assist", [participant, message], {
      env: { ...process.env, CAMPFIRE_COMMUNICATION_ENABLED: "false", CAMPFIRE_ASSISTANT_MODE: "1" },
      stdio: ["ignore", "pipe", "pipe"]
    });
    let stdout = "", stderr = "";
    child.stdout.on("data", d => stdout += d);
    child.stderr.on("data", d => stderr += d);
    const timer = setTimeout(() => child.kill("SIGTERM"), askTimeout * 1000);
    child.on("error", err => { clearTimeout(timer); reject(err); });
    child.on("close", code => {
      clearTimeout(timer);
      if (code === 0) resolve(stdout);
      else reject(new Error(stderr || `Assistant exited ${code}`));
    });
  });
}

const server = new McpServer({ name: "campfire", version: "0.1.0" });

server.tool("participants", "List Campfire participants currently available for communication.", {}, async () => {
  requireEnabled();
  return { content: [{ type: "text", text: participantNames().join("\n") }] };
});

server.tool("message", "Leave a one-way message for another participant. It is delivered with their next primary turn and does not start them.", {
  participant: z.string(), message: z.string().min(1)
}, async ({ participant, message }) => {
  assertTarget(participant);
  const dir = path.join(inboxRoot, participant);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, `${Date.now()}-${runId}-${current}.txt`), `From: ${current}\nRun: ${runId}\n\n${message}\n`);
  log("MESSAGE", participant);
  return { content: [{ type: "text", text: `Message queued for ${participant}.` }] };
});

server.tool("handoff", "Set or replace the outgoing handoff. It becomes effective only after the current primary turn exits.", {
  participant: z.string(), message: z.string().min(1)
}, async ({ participant, message }) => {
  assertTarget(participant);
  fs.writeFileSync(handoff, `${participant}\n${message}`);
  log("HANDOFF", participant);
  return { content: [{ type: "text", text: `Handoff prepared for ${participant}; it takes effect when this turn exits.` }] };
});

server.tool("ask", "Ask another participant to work in a fresh temporary session and return its answer. Independent ask calls may run concurrently.", {
  participant: z.string(), message: z.string().min(1)
}, async ({ participant, message }) => {
  assertTarget(participant);
  log("ASK", participant, "state=STARTING");
  try {
    const answer = await runAssistant(participant, message);
    log("ASK", participant, "state=FINISHED exit=0");
    return { content: [{ type: "text", text: answer }] };
  } catch (err) {
    log("ASK", participant, "state=FAILED");
    throw err;
  }
});

await server.connect(new StdioServerTransport());
