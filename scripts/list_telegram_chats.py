#!/usr/bin/env python
import argparse
import json
from pathlib import Path

import yaml
from telethon.sync import TelegramClient


def load_config(config_path: Path) -> dict:
    with config_path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def resolve_path(config_path: Path, value: str, default_relative: str) -> Path:
    if value:
        p = Path(value)
    else:
        p = Path(default_relative)
    if not p.is_absolute():
        p = config_path.parent / p
    return p


def main() -> int:
    parser = argparse.ArgumentParser(description="List Telegram dialogs (chats, groups, channels).")
    parser.add_argument("--config", required=True, help="Path to YAML config file")
    parser.add_argument("--json", action="store_true", help="Output JSONL records")
    parser.add_argument("--limit", type=int, default=0, help="Limit number of chats (0 for all)")
    args = parser.parse_args()

    config_path = Path(args.config).expanduser().resolve()
    cfg = load_config(config_path)

    session_path = resolve_path(config_path, cfg.get("session_file", ""), "data/telegram.session")

    api_id = int(cfg["api_id"])
    api_hash = cfg["api_hash"]
    phone = cfg.get("phone")

    with TelegramClient(str(session_path), api_id, api_hash) as client:
        client.start(phone=phone)

        count = 0
        for dialog in client.iter_dialogs():
            entity = dialog.entity
            record = {
                "id": entity.id,
                "title": getattr(entity, "title", None),
                "username": getattr(entity, "username", None),
                "is_user": dialog.is_user,
                "is_group": dialog.is_group,
                "is_channel": dialog.is_channel,
            }

            if args.json:
                print(json.dumps(record, ensure_ascii=False))
            else:
                title = record["title"] or record["username"] or "(no title)"
                kind = "channel" if record["is_channel"] else "group" if record["is_group"] else "user" if record["is_user"] else "chat"
                print(f"{record['id']}\t{kind}\t{title}\t@{record['username'] or ''}")

            count += 1
            if args.limit > 0 and count >= args.limit:
                break

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
