#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const qrcode = require('qrcode-terminal');
const {
  default: makeWASocket,
  useMultiFileAuthState,
  DisconnectReason,
  Browsers,
  fetchLatestBaileysVersion,
} = require('@whiskeysockets/baileys');

function loadConfig(configPath) {
  const raw = fs.readFileSync(configPath, 'utf8');
  return yaml.load(raw) || {};
}

function resolvePath(configPath, value, defaultRelative) {
  const base = path.dirname(configPath);
  const p = value && value.length ? value : defaultRelative;
  return path.isAbsolute(p) ? p : path.join(base, p);
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function isAuthPresent(authDir) {
  try {
    return fs.existsSync(path.join(authDir, 'creds.json'));
  } catch (_) {
    return false;
  }
}

async function start() {
  const args = process.argv.slice(2);
  const configIndex = args.indexOf('--config');
  if (configIndex === -1 || !args[configIndex + 1]) {
    console.error('Usage: whatsapp_login.js --config /path/to/config.yaml');
    process.exit(2);
  }

  const configPath = path.resolve(args[configIndex + 1]);
  const cfg = loadConfig(configPath);

  const authDir = resolvePath(
    configPath,
    cfg.whatsapp_auth_dir || 'data/whatsapp_auth',
    'data/whatsapp_auth'
  );

  ensureDir(authDir);

  if (isAuthPresent(authDir)) {
    console.log('[whatsapp] auth already present');
  }

  const { state, saveCreds } = await useMultiFileAuthState(authDir);
  const { version } = await fetchLatestBaileysVersion();

  const sock = makeWASocket({
    auth: state,
    version,
    browser: Browsers.macOS('Desktop'),
    shouldSyncHistoryMessage: () => false,
    syncFullHistory: false,
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', (update) => {
    const { connection, lastDisconnect } = update;
    if (update.qr) {
      console.log('[whatsapp] scan this QR code with WhatsApp -> Linked Devices');
      qrcode.generate(update.qr, { small: true });
    }
    if (connection === 'open') {
      console.log('[whatsapp] login successful');
      setTimeout(() => process.exit(0), 1000).unref();
    }
    if (connection === 'close') {
      const statusCode = lastDisconnect?.error?.output?.statusCode;
      if (statusCode === DisconnectReason.connectionReplaced || statusCode === 409) {
        console.error('[whatsapp] session replaced');
        process.exit(1);
      }
    }
  });
}

start().catch((err) => {
  console.error('[whatsapp] fatal error', err);
  process.exit(1);
});
