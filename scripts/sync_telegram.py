#!/usr/bin/env python
import argparse
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

import yaml
from telethon.sync import TelegramClient


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

    required = ["api_id", "api_hash", "phone", "chats", "output_jsonl", "state_file"]
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


def load_state(state_path: Path) -> dict:
    if not state_path.exists():
        return {}
    with state_path.open("r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            return {}


def save_state(state_path: Path, state: dict) -> None:
    state_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = state_path.with_suffix(".tmp")
    with tmp_path.open("w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    tmp_path.replace(state_path)


def build_record(msg, chat_id, chat_title, chat_username, run_id):
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
    parser = argparse.ArgumentParser(description="Sync Telegram chats to JSONL.")
    parser.add_argument("--config", required=True, help="Path to YAML config file")
    parser.add_argument("--rebuild", action="store_true", help="Ignore state and rebuild output JSONL")
    parser.add_argument("--initial-days", type=int, help="Override initial_days from config")
    args = parser.parse_args()

    config_path = Path(args.config).expanduser().resolve()
    cfg = load_config(config_path)

    session_path = resolve_path(config_path, cfg.get("session_file", ""), "data/telegram.session")
    output_path = resolve_path(config_path, cfg.get("output_jsonl", ""), "data/telegram_messages.jsonl")
    state_path = resolve_path(config_path, cfg.get("state_file", ""), "data/telegram_state.json")

    output_path.parent.mkdir(parents=True, exist_ok=True)

    api_id = int(cfg["api_id"])
    api_hash = cfg["api_hash"]
    phone = cfg["phone"]
    chats = cfg["chats"]
    initial_limit = int(cfg.get("initial_limit", 0))
    initial_days = cfg.get("initial_days")
    if args.initial_days is not None:
        initial_days = args.initial_days
    if initial_days is not None:
        initial_days = int(initial_days)

    state = {} if args.rebuild else load_state(state_path)
    run_id = datetime.now(timezone.utc).isoformat()

    with TelegramClient(str(session_path), api_id, api_hash) as client:
        client.start(phone=phone)
        out_mode = "w" if args.rebuild else "a"
        with output_path.open(out_mode, encoding="utf-8") as out:
            for chat in chats:
                try:
                    entity = client.get_entity(chat)
                except Exception as exc:
                    print(f"[sync] failed to resolve chat {chat}: {exc}", file=sys.stderr)
                    continue

                chat_id = entity.id
                chat_title = getattr(entity, "title", None)
                chat_username = getattr(entity, "username", None)

                last_id = int(state.get(str(chat_id), 0))
                is_initial = last_id == 0 and (initial_limit > 0 or (initial_days and initial_days > 0))

                print(f"[sync] chat={chat_title or chat_username or chat_id} last_id={last_id}")

                try:
                    if is_initial:
                        newest_first = []
                        if initial_days and initial_days > 0:
                            cutoff = datetime.now(timezone.utc) - timedelta(days=initial_days)
                            for msg in client.iter_messages(entity):
                                if msg.date < cutoff:
                                    break
                                newest_first.append(msg)
                        else:
                            # Fetch latest N messages, then write oldest->newest
                            newest_first = list(client.iter_messages(entity, limit=initial_limit))

                        for msg in reversed(newest_first):
                            record = build_record(msg, chat_id, chat_title, chat_username, run_id)
                            out.write(json.dumps(record, ensure_ascii=False) + "\n")

                        if newest_first:
                            last_id = max(m.id for m in newest_first)
                    else:
                        iterator = client.iter_messages(entity, min_id=last_id, reverse=True)
                        for msg in iterator:
                            record = build_record(msg, chat_id, chat_title, chat_username, run_id)
                            out.write(json.dumps(record, ensure_ascii=False) + "\n")
                            if msg.id > last_id:
                                last_id = msg.id
                except Exception as exc:
                    print(f"[sync] failed to sync chat {chat}: {exc}", file=sys.stderr)
                    continue

                state[str(chat_id)] = last_id

    save_state(state_path, state)
    print("[sync] done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
