#!/usr/bin/env python
import argparse
import json
import sys
from collections import deque
from datetime import datetime, timedelta, timezone
from pathlib import Path

import yaml


def load_config(config_path: Path) -> dict:
    with config_path.open("r", encoding="utf-8") as f:
        cfg = yaml.safe_load(f) or {}
    return cfg


def resolve_path(config_path: Path, value: str, default_relative: str) -> Path:
    if value:
        p = Path(value)
    else:
        p = Path(default_relative)
    if not p.is_absolute():
        p = config_path.parent / p
    return p


def parse_dt(value: str) -> datetime:
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    dt = datetime.fromisoformat(value)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def match_chat(rec: dict, filters) -> bool:
    if not filters:
        return True
    chat_id = str(rec.get("chat_id", ""))
    chat_username = rec.get("chat_username") or ""
    chat_title = rec.get("chat_title") or ""

    for f in filters:
        if f.isdigit() and chat_id == f:
            return True
        if f.startswith("@") and chat_username and f[1:].lower() == chat_username.lower():
            return True
        if f.lower() in chat_title.lower():
            return True
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Query Telegram JSONL store.")
    parser.add_argument("--config", required=True, help="Path to YAML config file")
    parser.add_argument("--chat", action="append", help="Chat filter (@username, id, or title substring)")
    parser.add_argument("--contains", help="Case-insensitive substring match on message text")
    parser.add_argument("--after", help="ISO datetime; include messages >= this time")
    parser.add_argument("--before", help="ISO datetime; include messages <= this time")
    parser.add_argument("--since-days", type=int, help="Include messages from the last N days")
    parser.add_argument("--limit", type=int, default=200, help="Max records to output (0 for unlimited)")
    parser.add_argument("--latest", action="store_true", help="Return latest N matches (requires --limit > 0)")
    args = parser.parse_args()

    if args.latest and args.limit <= 0:
        print("--latest requires --limit > 0", file=sys.stderr)
        return 2

    config_path = Path(args.config).expanduser().resolve()
    cfg = load_config(config_path)

    output_path = resolve_path(config_path, cfg.get("output_jsonl", ""), "data/telegram_messages.jsonl")
    if not output_path.exists():
        print(f"JSONL not found: {output_path}", file=sys.stderr)
        return 1

    after_dt = parse_dt(args.after) if args.after else None
    before_dt = parse_dt(args.before) if args.before else None
    if args.since_days is not None:
        after_dt = datetime.now(timezone.utc) - timedelta(days=args.since_days)

    contains = args.contains.lower() if args.contains else None

    buffer = deque(maxlen=args.limit) if args.latest and args.limit > 0 else None
    count = 0

    with output_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue

            if not match_chat(rec, args.chat):
                continue

            rec_date = None
            if rec.get("date"):
                try:
                    rec_date = parse_dt(rec["date"])
                except Exception:
                    rec_date = None

            if after_dt and rec_date and rec_date < after_dt:
                continue
            if before_dt and rec_date and rec_date > before_dt:
                continue

            text = rec.get("text") or ""
            if contains and contains not in text.lower():
                continue

            if buffer is not None:
                buffer.append(rec)
                continue

            print(json.dumps(rec, ensure_ascii=False))
            count += 1
            if args.limit > 0 and count >= args.limit:
                break

    if buffer is not None:
        for rec in buffer:
            print(json.dumps(rec, ensure_ascii=False))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
