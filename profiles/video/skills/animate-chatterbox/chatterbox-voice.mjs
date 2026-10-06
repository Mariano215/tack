#!/usr/bin/env node
// Chatterbox takes for an animate piece: one WAV per script line, from a self-hosted Chatterbox server.
//   usage: node chatterbox-voice.mjs pieces/<name> [--only id,id] [--force] [--dry-run]
// reads  <piece>/voice/script.json (animate's format), writes <piece>/voice/<id>.wav and sets "file" on each line.
// Then run animate's tools/voice.mjs on the piece as usual: it times the words and builds voice.wav.
//
// config, from the environment (nothing machine-specific lives in this file):
//   CHATTERBOX_URL     base URL of the server, e.g. http://<tailscale-host>:<port>   (required)
//   CHATTERBOX_VOICE   the voice to speak with, as the server names it               (required)
//   CHATTERBOX_API     "tts" (default): POST /v1/tts { text, voice }   (the self-hosted FastAPI wrapper)
//                      "openai": POST /v1/audio/speech { input, voice }
//                      "native": POST /tts { text, voice_mode: "predefined", predefined_voice_id }
//   CHATTERBOX_EXAGGERATION, CHATTERBOX_CFG_WEIGHT, CHATTERBOX_TEMPERATURE, CHATTERBOX_SEED   optional, passed through
//                      (openai and native only; the tts wrapper takes text and voice and nothing else)
//   CHATTERBOX_TIMEOUT seconds per line (default 180)
import fs from 'node:fs';
import path from 'node:path';

const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const has = (k) => argv.includes(k);
if (!argv[0] || argv[0].startsWith('--')) {
  console.error('usage: node chatterbox-voice.mjs pieces/<name> [--only id,id] [--force] [--dry-run]');
  process.exit(2);
}

const BASE = (process.env.CHATTERBOX_URL || '').replace(/\/+$/, '');
const VOICE = process.env.CHATTERBOX_VOICE || '';
const API = (process.env.CHATTERBOX_API || 'tts').toLowerCase();
if (!BASE || !VOICE) {
  console.error('CHATTERBOX_URL and CHATTERBOX_VOICE must be set. Fix: export them in your shell rc or the profile env, then rerun.');
  process.exit(2);
}
if (!['tts', 'openai', 'native'].includes(API)) { console.error(`CHATTERBOX_API must be "tts", "openai" or "native", got "${API}"`); process.exit(2); }

const num = (k) => (process.env[k] !== undefined && process.env[k] !== '' ? Number(process.env[k]) : undefined);
const tuning = {
  exaggeration: num('CHATTERBOX_EXAGGERATION'),
  cfg_weight: num('CHATTERBOX_CFG_WEIGHT'),
  temperature: num('CHATTERBOX_TEMPERATURE'),
  seed: num('CHATTERBOX_SEED'),
};
for (const k of Object.keys(tuning)) if (tuning[k] === undefined || Number.isNaN(tuning[k])) delete tuning[k];

const ROOT = path.resolve(argv[0]);
const VDIR = path.join(ROOT, 'voice');
const SCRIPT = path.join(VDIR, 'script.json');
if (!fs.existsSync(SCRIPT)) { console.error(`no script at ${SCRIPT}. Fix: write the voice script first (animate SKILL.md, Voice-over).`); process.exit(1); }
const S = JSON.parse(fs.readFileSync(SCRIPT, 'utf8'));
const only = opt('--only') ? new Set(opt('--only').split(',').map((s) => s.trim())) : null;
const timeoutMs = (num('CHATTERBOX_TIMEOUT') ?? 180) * 1000;

function request(text) {
  if (API === 'tts') return { url: `${BASE}/v1/tts`, body: { text, voice: VOICE } };
  if (API === 'openai') {
    return { url: `${BASE}/v1/audio/speech`, body: { model: 'chatterbox', input: text, voice: VOICE, response_format: 'wav', ...tuning } };
  }
  return { url: `${BASE}/tts`, body: { text, voice_mode: 'predefined', predefined_voice_id: VOICE, output_format: 'wav', split_text: false, ...tuning } };
}

async function take(text, out) {
  const { url, body } = request(text);
  const ctl = new AbortController();
  const timer = setTimeout(() => ctl.abort(), timeoutMs);
  try {
    const r = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body), signal: ctl.signal });
    const buf = Buffer.from(await r.arrayBuffer());
    if (!r.ok) throw new Error(`HTTP ${r.status} from ${url}: ${buf.toString('utf8').slice(0, 300)}`);
    if (buf.length < 44 || buf.toString('ascii', 0, 4) !== 'RIFF') {
      throw new Error(`${url} did not return WAV audio (${buf.length} bytes, content-type ${r.headers.get('content-type')}). Fix: check CHATTERBOX_API matches the server.`);
    }
    fs.writeFileSync(out, buf);
    return buf.length;
  } finally { clearTimeout(timer); }
}

let made = 0, skipped = 0;
for (const [i, L] of S.lines.entries()) {
  const id = L.id || `l${i + 1}`;
  if (only && !only.has(id)) continue;
  const name = `${id}.wav`, out = path.join(VDIR, name);
  if (fs.existsSync(out) && !has('--force')) { skipped++; L.file = name; continue; }
  if (has('--dry-run')) { console.log(`would take "${id}": ${L.text}`); continue; }
  process.stdout.write(`take ${id} ... `);
  try {
    const bytes = await take(L.text, out);
    L.file = name; made++;
    console.log(`${(bytes / 1024).toFixed(0)} KB`);
  } catch (e) {
    console.log('failed');
    console.error(e.name === 'AbortError' ? `timed out after ${timeoutMs / 1000}s. Fix: raise CHATTERBOX_TIMEOUT or check the server is up.` : e.message);
    process.exit(1);
  }
}
if (!has('--dry-run')) fs.writeFileSync(SCRIPT, JSON.stringify(S, null, 2) + '\n');
console.log(`chatterbox: ${made} new take(s), ${skipped} kept (use --force to redo). Next: node <animate>/tools/voice.mjs ${argv[0]}`);
