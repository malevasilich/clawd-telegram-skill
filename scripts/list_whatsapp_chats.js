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

function recordFromChat(chat) {
  return {
    id: chat.id,
    name: chat.name || chat.subject || null,
    is_group: chat.id?.endsWith('@g.us') || false,
    is_user: chat.id?.endsWith('@s.whatsapp.net') || false,
  };
}

async function start() {
  const args = process.argv.slice(2);
  const configIndex = args.indexOf('--config');
  if (configIndex === -1 || !args[configIndex + 1]) {
    console.error('Usage: list_whatsapp_chats.js --config /path/to/config.yaml [--json]');
    process.exit(2);
  }
  const jsonOut = args.includes('--json');
  const limitIndex = args.indexOf('--limit');
  const limit = limitIndex !== -1 ? Number(args[limitIndex + 1] || 0) : 0;

  const configPath = path.resolve(args[configIndex + 1]);
  const cfg = loadConfig(configPath);

  const authDir = resolvePath(
    configPath,
    cfg.whatsapp_auth_dir || 'data/whatsapp_auth',
    'data/whatsapp_auth'
  );
  ensureDir(authDir);

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

  const chatsMap = new Map();
  let printed = false;
  const addChat = (chat) => {
    if (chat?.id) chatsMap.set(chat.id, recordFromChat(chat));
  };
  const printChats = (extraChats = []) => {
    if (printed) return;
    for (const c of extraChats) addChat(c);
    const all = Array.from(chatsMap.values());
    const sliced = limit > 0 ? all.slice(0, limit) : all;

    for (const r of sliced) {
      if (jsonOut) {
        console.log(JSON.stringify(r));
      } else {
        const kind = r.is_group ? 'group' : r.is_user ? 'user' : 'chat';
        console.log(`${r.id}\t${kind}\t${r.name || ''}`);
      }
    }
    printed = true;
    sock.end?.(new Error('done'));
    setTimeout(() => process.exit(0), 200).unref();
  };

  sock.ev.on('chats.set', (payload) => {
    if (payload?.chats) {
      for (const c of payload.chats) addChat(c);
    }
  });
  sock.ev.on('chats.upsert', (chats) => {
    if (Array.isArray(chats)) {
      for (const c of chats) addChat(c);
    }
  });

  sock.ev.on('connection.update', async (update) => {
    const { connection, lastDisconnect } = update;
    if (update.qr) {
      console.log('[whatsapp] scan this QR code with WhatsApp -> Linked Devices');
      qrcode.generate(update.qr, { small: true });
    }
    if (connection === 'open') {
      // Try to fetch group metadata to enrich listing
      let groups = [];
      try {
        const res = await sock.groupFetchAllParticipating();
        groups = Object.values(res || {});
      } catch (_) {
        groups = [];
      }

      // Give a moment for chats to sync, then print
      setTimeout(() => printChats(groups), 3000).unref();
    }

    if (connection === 'close') {
      const statusCode = lastDisconnect?.error?.output?.statusCode;
      if (statusCode === DisconnectReason.restartRequired) {
        // Let caller restart
        process.exit(1);
      }
    }
  });
}

start().catch((err) => {
  console.error('[whatsapp] fatal error', err);
  process.exit(1);
});
