#!/usr/bin/env python
import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import yaml
from telethon import TelegramClient, events


def _resolve_env_value(value):
    if value is None:
        return None
    if isinstance(value, str):
        key = None
        if value.startswith("${") and value.endswith("}"):
            key = value[2:-1]
        elif value.startswith("$"):
            key = value[1:]
        if key:
            return os.environ.get(key)
    return value


def load_config(config_path: Path) -> dict:
    with config_path.open("r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}

    cfg["api_id"] = _resolve_env_value(cfg.get("api_id")) or os.environ.get("TG_API_ID")
    cfg["api_hash"] = _resolve_env_value(cfg.get("api_hash")) or os.environ.get("TG_API_HASH")
    cfg["phone"] = _resolve_env_value(cfg.get("phone")) or os.environ.get("TG_PHONE")

    required = ["api_id", "api_hash", "phone", "chats", "output_jsonl"]
    missing = [k for k in required if k not in cfg]
    if missing:
        raise ValueError(f"Missing config keys: {', '.join(missing)}")

    return cfg


def resolve_path(config_path: Path, value: str, default_relative: str) -> Path:
    if value:
        p = Path(value)
    else:
        p = Path(default_relative)
    if not p.is_absolute():
        p = config_path.parent / p
    return p


def build_record(msg, chat, run_id):
    chat_id = getattr(chat, "id", None)
    chat_title = getattr(chat, "title", None)
    chat_username = getattr(chat, "username", None)

    sender_username = None
    if msg.sender:
        sender_username = getattr(msg.sender, "username", None)

    return {
        "source": "telegram",
        "chat_id": chat_id,
        "chat_title": chat_title,
        "chat_username": chat_username,
        "message_id": msg.id,
        "date": msg.date.isoformat(),
        "sender_id": msg.sender_id,
        "sender_username": sender_username,
        "text": msg.message or "",
        "is_service": msg.action is not None,
        "has_media": msg.media is not None,
        "reply_to_msg_id": msg.reply_to_msg_id,
        "run_id": run_id,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Listen for new Telegram messages and append to JSONL.")
    parser.add_argument("--config", required=True, help="Path to YAML config file")
    parser.add_argument("--quiet", action="store_true", help="Disable per-message logs")
    parser.add_argument("--verbose", action="store_true", help="Enable per-message logs")
    args = parser.parse_args()

    config_path = Path(args.config).expanduser().resolve()
    cfg = load_config(config_path)

    session_path = resolve_path(config_path, cfg.get("session_file", ""), "data/telegram.session")
    output_path = resolve_path(config_path, cfg.get("output_jsonl", ""), "data/telegram_messages.jsonl")
    output_path.parent.mkdir(parents=True, exist_ok=True)

    api_id = int(cfg["api_id"])
    api_hash = cfg["api_hash"]
    phone = cfg["phone"]
    chats = cfg["chats"]

    env_log = os.environ.get("LISTENER_LOG", "").lower()
    env_quiet = env_log == "quiet"
    env_verbose = env_log == "verbose"
    log_messages = args.verbose or env_verbose or (not args.quiet and not env_quiet)
    run_id = datetime.now(timezone.utc).isoformat()

    max_retries = int(os.environ.get("LISTENER_MAX_RETRIES", "5"))
    base_delay = int(os.environ.get("LISTENER_RETRY_SECONDS", "5"))
    attempt = 0

    while True:
        client = TelegramClient(str(session_path), api_id, api_hash)

        @client.on(events.NewMessage(chats=chats))
        async def handler(event):
            msg = event.message
            chat = await event.get_chat()
            record = build_record(msg, chat, run_id)
            with output_path.open("a", encoding="utf-8") as out:
                out.write(json.dumps(record, ensure_ascii=False) + "\n")
            if log_messages:
                preview = (record["text"] or "").replace("\n", " ")
                preview = " ".join(preview.split())[:120]
                print(f"[telegram] saved message chat={record['chat_id']} id={record['message_id']} text=\"{preview}\"")

        try:
            client.start(phone=phone)
            print("[telegram] listener started")
            client.run_until_disconnected()
            print("[telegram] disconnected", file=sys.stderr)
        except Exception as exc:
            print(f"[telegram] disconnected: {exc}", file=sys.stderr)
        finally:
            try:
                client.disconnect()
            except Exception:
                pass
        attempt += 1
        if attempt >= max_retries:
            print("[telegram] max reconnect attempts reached; exiting with error", file=sys.stderr)
            return 1
        delay = base_delay * (2 ** (attempt - 1))
        print(f"[telegram] reconnecting in {delay}s (attempt {attempt}/{max_retries})", file=sys.stderr)
        time.sleep(delay)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
