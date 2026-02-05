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
  getContentType,
} = require('@whiskeysockets/baileys');

function loadConfig(configPath) {
  const raw = fs.readFileSync(configPath, 'utf8');
  const cfg = yaml.load(raw) || {};
  return cfg;
}

function resolvePath(configPath, value, defaultRelative) {
  const base = path.dirname(configPath);
  const p = value && value.length ? value : defaultRelative;
  return path.isAbsolute(p) ? p : path.join(base, p);
}

function normalizeChatId(id) {
  if (!id || typeof id !== 'string') return id;
  if (id.includes('@')) return id;
  if (id.includes('-')) return `${id}@g.us`;
  const digits = id.replace(/\\+/g, '');
  return `${digits}@s.whatsapp.net`;
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function toIso(tsSeconds) {
  if (!tsSeconds) return null;
  const ms = Number(tsSeconds) * 1000;
  return new Date(ms).toISOString();
}

function extractText(message) {
  if (!message) return '';
  const type = getContentType(message);
  if (!type) return '';
  const msg = message[type] || {};

  if (type === 'conversation') return message.conversation || '';
  if (type === 'extendedTextMessage') return msg.text || '';
  if (type === 'imageMessage' || type === 'videoMessage' || type === 'documentMessage') {
    return msg.caption || '';
  }
  if (type === 'buttonsResponseMessage') return msg.selectedButtonId || '';
  if (type === 'listResponseMessage') return msg.singleSelectReply?.selectedRowId || '';
  if (type === 'templateButtonReplyMessage') return msg.selectedId || '';
  return '';
}

function hasMedia(message) {
  if (!message) return false;
  const type = getContentType(message);
  return [
    'imageMessage',
    'videoMessage',
    'audioMessage',
    'documentMessage',
    'stickerMessage',
  ].includes(type);
}

async function start() {
  const args = process.argv.slice(2);
  const configIndex = args.indexOf('--config');
  if (configIndex === -1 || !args[configIndex + 1]) {
    console.error('Usage: whatsapp_listen.js --config /path/to/config.yaml');
    process.exit(2);
  }
  const verbose = args.includes('--verbose');
  const quiet = args.includes('--quiet');
  const envLog = (process.env.LISTENER_LOG || '').toLowerCase();
  const envQuiet = envLog === 'quiet';
  const envVerbose = envLog === 'verbose';
  const logMessages = verbose || envVerbose || (!quiet && !envQuiet);

  const configPath = path.resolve(args[configIndex + 1]);
  const cfg = loadConfig(configPath);

  const outputPath = resolvePath(
    configPath,
    cfg.whatsapp_output_jsonl || cfg.output_jsonl || 'data/messages.jsonl',
    'data/messages.jsonl'
  );
  const authDir = resolvePath(
    configPath,
    cfg.whatsapp_auth_dir || 'data/whatsapp_auth',
    'data/whatsapp_auth'
  );

  ensureDir(path.dirname(outputPath));
  ensureDir(authDir);

  const { state, saveCreds } = await useMultiFileAuthState(authDir);
  const { version } = await fetchLatestBaileysVersion();
  const chatAllowList = Array.isArray(cfg.whatsapp_chats)
    ? cfg.whatsapp_chats.map((c) => normalizeChatId(String(c)))
    : [];

  const maxRetries = Number(process.env.LISTENER_MAX_RETRIES || 5);
  const baseDelayMs = Number(process.env.LISTENER_RETRY_SECONDS || 5) * 1000;
  let attempt = 0;
  let sock = null;
  let reconnectScheduled = false;

  const runId = new Date().toISOString();
  const stream = fs.createWriteStream(outputPath, { flags: 'a' });

  const scheduleReconnect = (reason) => {
    if (reconnectScheduled) return;
    if (attempt >= maxRetries) {
      console.error('[whatsapp] max reconnect attempts reached; exiting with error');
      process.exit(1);
    }
    attempt += 1;
    reconnectScheduled = true;
    const delayMs = baseDelayMs * (2 ** (attempt - 1));
    console.log(`[whatsapp] reconnecting in ${delayMs / 1000}s (attempt ${attempt}/${maxRetries})`);
    setTimeout(() => {
      reconnectScheduled = false;
      try {
        sock?.end?.(new Error('reconnect'));
      } catch (_) {}
      initSocket();
    }, delayMs).unref();
  };

  const initSocket = () => {
    sock = makeWASocket({
      auth: state,
      version,
      browser: Browsers.macOS('Desktop'),
      // Disable history sync; we only want new incoming messages
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
      if (connection === 'close') {
        const statusCode = lastDisconnect?.error?.output?.statusCode;
        if (statusCode === DisconnectReason.connectionReplaced || statusCode === 409) {
          console.error('[whatsapp] session replaced: another client is using the same auth. Stop other listener or use a separate auth dir.');
          return;
        }
        if (statusCode === DisconnectReason.restartRequired) {
          console.log('[whatsapp] restart required');
          scheduleReconnect('restartRequired');
        } else {
          console.log('[whatsapp] connection closed');
          scheduleReconnect('closed');
        }
      }
      if (connection === 'open') {
        console.log('[whatsapp] connected');
      }
    });

    sock.ev.on('messages.upsert', ({ type, messages }) => {
      if (type !== 'notify') return; // only new messages
      for (const msg of messages) {
        if (!msg || msg.key?.fromMe) continue; // only incoming

        const chatId = msg.key?.remoteJid || null;
        if (chatAllowList.length > 0 && chatId && !chatAllowList.includes(chatId)) {
          continue;
        }
        const senderId = msg.key?.participant || chatId;
        const record = {
          source: 'whatsapp',
          chat_id: chatId,
          chat_title: null,
          chat_username: null,
          message_id: msg.key?.id || null,
          date: toIso(msg.messageTimestamp),
          sender_id: senderId,
          sender_username: null,
          text: extractText(msg.message),
          is_service: Boolean(msg.messageStubType),
          has_media: hasMedia(msg.message),
          reply_to_msg_id: msg.message?.extendedTextMessage?.contextInfo?.stanzaId || null,
          run_id: runId,
        };

        stream.write(JSON.stringify(record) + '\\n');
        if (logMessages) {
          const preview = (record.text || '').replace(/\\s+/g, ' ').slice(0, 120);
          console.log(`[whatsapp] saved message chat=${chatId} id=${record.message_id} text="${preview}"`);
        }
      }
    });
  };

  initSocket();
}

start().catch((err) => {
  console.error('[whatsapp] fatal error', err);
  process.exit(1);
});
