// Render Gemini CLI's JSONL stream as short, live terminal updates. Do not
// print user prompts, tool arguments, or full tool results into run logs.
const readline = require('node:readline');

let textOpen = false;
let lastEventAt = Date.now();

function brief(value) {
  return String(value ?? '').replace(/\s+/g, ' ').slice(0, 500);
}

function line(message) {
  if (textOpen) {
    process.stdout.write('\n');
    textOpen = false;
  }
  process.stdout.write(`${message}\n`);
}

const heartbeat = setInterval(() => {
  const seconds = Math.floor((Date.now() - lastEventAt) / 1000);
  if (seconds >= 30) line(`[gemini] no new CLI event for ${seconds}s`);
}, 30000);

const input = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });
input.on('line', (raw) => {
  lastEventAt = Date.now();
  let event;
  try {
    event = JSON.parse(raw);
  } catch {
    line(`[gemini] unstructured output: ${brief(raw)}`);
    return;
  }
  switch (event.type) {
    case 'init':
      line(`[gemini] session started${event.model ? ` model=${brief(event.model)}` : ''}`);
      break;
    case 'message':
      if (event.role === 'assistant' && typeof event.content === 'string') {
        process.stdout.write(event.content);
        textOpen = !event.content.endsWith('\n');
      }
      break;
    case 'tool_use':
      line(`[gemini] tool: ${brief(event.tool_name || 'unknown')}`);
      break;
    case 'tool_result':
      if (event.status === 'error') {
        line(`[gemini] tool error: ${brief(event.error?.message || 'unknown error')}`);
      }
      break;
    case 'error':
      line(`[gemini] error: ${brief(event.message || event.error?.message || 'unknown error')}`);
      break;
    case 'result':
      line(`[gemini] finished status=${brief(event.status || 'unknown')}`);
      break;
  }
});
input.on('close', () => {
  clearInterval(heartbeat);
  if (textOpen) process.stdout.write('\n');
});
