---
name: clawdbot-telegram
description: Read specific Telegram chats via Telethon, sync messages to JSONL, and provide query access for clawdbot.
---

# Clawdbot Telegram Sync (Telethon)

Use this skill when you need to read specific Telegram chats (listed in a config file), store the messages locally in JSONL, and make those messages available for clawdbot to analyze or answer questions.

## Quick Start

1. Create a config file (YAML). You can start from `assets/config.example.yaml`.
2. Install dependencies:
   - Python: `pip install telethon pyyaml`
   - Node: `scripts/install_node_deps.sh`
3. Run sync:
   - `python scripts/sync_telegram.py --config /path/to/config.yaml`
   - Rebuild: `python scripts/sync_telegram.py --config /path/to/config.yaml --rebuild`
   - Live listener: `python scripts/telegram_listen.py --config /path/to/config.yaml`
4. Query for clawdbot:
   - `python scripts/query_telegram.py --config /path/to/config.yaml --contains "keyword" --limit 100`
5. List Telegram chats (to get IDs for config):
   - `python scripts/list_telegram_chats.py --config /path/to/config.yaml`
5. Analyze latest (local clawdbot):
   - `scripts/analyze_latest.sh`
6. Start WhatsApp listener (new messages only):
   - `node scripts/whatsapp_listen.js --config /path/to/config.yaml`
   - Quiet: `LISTENER_LOG=quiet node scripts/whatsapp_listen.js --config /path/to/config.yaml`
   - Verbose: `LISTENER_LOG=verbose node scripts/whatsapp_listen.js --config /path/to/config.yaml`
7. Start both (Telegram + WhatsApp listeners):
   - `LISTENER_LOG=quiet scripts/start_listeners.sh`
   - Reconnect control: `LISTENER_MAX_RETRIES=5 LISTENER_RETRY_SECONDS=5 scripts/start_listeners.sh`
8. List WhatsApp chats (to get IDs for config):
   - `node scripts/list_whatsapp_chats.js --config /path/to/config.yaml`
9. Install as launchd service:
   - `scripts/install_launchd.sh`
   - On-demand: `scripts/install_launchd.sh --on-demand`
   - Keepalive: `scripts/install_launchd_keepalive.sh`
   - Status: `launchctl list | grep whatsapp_telegram_listeners`
   - Detailed: `scripts/status_launchd.sh`
   - Start: `scripts/start_launchd.sh`
   - Stop: `scripts/stop_launchd.sh`
   - Restart: `scripts/restart_launchd.sh`
   - Status + logs: `LINES=50 scripts/status_and_logs.sh`
   - Stop: `launchctl stop gui/$(id -u)/malevasilich.whatsapp_telegram_listeners`
   - Uninstall: `scripts/uninstall_launchd.sh`

## What This Skill Provides

- `scripts/sync_telegram.py`:
  - Connects to Telegram using Telethon.
  - Reads chats listed in config.
  - Appends messages to a JSONL file.
  - Maintains a local state file for incremental syncs.
- `scripts/query_telegram.py`:
  - Filters the JSONL store by chat, time, or keyword.
  - Outputs JSONL to stdout for clawdbot ingestion.
- `scripts/whatsapp_listen.js`:
  - Connects via WhatsApp Web (QR login).
  - Captures new incoming messages only.
  - Appends records to JSONL with `source: "whatsapp"`.
- `references/schema.md`:
  - JSONL schema and field meanings.

## Configuration Notes

- You must provide Telegram `api_id` and `api_hash`. These are created at https://my.telegram.org.
- The first run may require an interactive login (code sent to Telegram).
- The session file is stored locally; keep it private.

## When to Load References

- Use `references/schema.md` if you need field-level details or want to map fields for downstream analysis.

## Common Tasks

- **Add chats**: Update the `chats` list in the config.
- **Change output**: Update `output_jsonl` in the config.
- **Initial sync window**: Use `initial_days` to pull only recent messages (e.g., last 1 day).
- **Incremental sync**: The state file tracks last message id per chat.
