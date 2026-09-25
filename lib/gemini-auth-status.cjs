// Gemini CLI 0.61's file keychain encrypts saved API keys with a key derived
// from the container hostname and user. Check that this container can decrypt
// its saved key without sending a request or printing the credential.
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

try {
  const file = path.join(os.homedir(), '.gemini', 'gemini-credentials.json');
  if (fs.statSync(file).size > 65536) process.exit(1);
  const parts = fs.readFileSync(file, 'utf8').split(':');
  if (parts.length !== 3 || !/^[0-9a-f]{24}$/i.test(parts[0]) ||
      !/^[0-9a-f]{32}$/i.test(parts[1]) || !/^(?:[0-9a-f]{2})+$/i.test(parts[2])) {
    process.exit(1);
  }
  const salt = `${os.hostname()}-${os.userInfo().username}-gemini-cli`;
  const key = crypto.scryptSync('gemini-cli-oauth', salt, 32);
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(parts[0], 'hex'));
  decipher.setAuthTag(Buffer.from(parts[1], 'hex'));
  const data = JSON.parse(decipher.update(parts[2], 'hex', 'utf8') + decipher.final('utf8'));
  const savedKey = data?.['gemini-cli-api-key']?.['default-api-key'];
  process.exit(typeof savedKey === 'string' && savedKey.length > 0 ? 0 : 1);
} catch {
  process.exit(1);
}
