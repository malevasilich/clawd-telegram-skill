---
name: clawdbot-telegram
description: Read specific Telegram chats via Telethon, sync messages to JSONL, and provide query access for clawdbot.
---

# Clawdbot Telegram Sync (Telethon)

Use this skill when you need to read specific Telegram chats (listed in a config file), store the messages locally in JSONL, and make those messages available for clawdbot to analyze or answer questions.

## Quick Start

1. Create a config file (YAML). You can start from `assets/config.example.yaml`.
2. Install dependencies:
   - `pip install telethon pyyaml`
3. Run sync:
   - `python scripts/sync_telegram.py --config /path/to/config.yaml`
   - Rebuild: `python scripts/sync_telegram.py --config /path/to/config.yaml --rebuild`
4. Query for clawdbot:
   - `python scripts/query_telegram.py --config /path/to/config.yaml --contains "keyword" --limit 100`
5. Analyze latest (local clawdbot):
   - `scripts/analyze_latest.sh`

## What This Skill Provides

- `scripts/sync_telegram.py`:
  - Connects to Telegram using Telethon.
  - Reads chats listed in config.
  - Appends messages to a JSONL file.
  - Maintains a local state file for incremental syncs.
- `scripts/query_telegram.py`:
  - Filters the JSONL store by chat, time, or keyword.
  - Outputs JSONL to stdout for clawdbot ingestion.
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
