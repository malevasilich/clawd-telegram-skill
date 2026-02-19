#!/usr/bin/env python
import argparse
import os
from getpass import getpass
from pathlib import Path

import yaml
from telethon import TelegramClient
from telethon.errors import SessionPasswordNeededError


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

    required = ["api_id", "api_hash"]
    missing = [k for k in required if not cfg.get(k)]
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Interactive Telegram login (create session file).")
    parser.add_argument("--config", required=True, help="Path to YAML config file")
    args = parser.parse_args()

    config_path = Path(args.config).expanduser().resolve()
    cfg = load_config(config_path)

    listener_session = cfg.get("telegram_listener_session_file") or cfg.get("listener_session_file")
    session_path = resolve_path(
        config_path,
        listener_session if listener_session is not None else cfg.get("session_file", ""),
        "data/telegram_listener.session",
    )

    api_id = int(cfg["api_id"])
    api_hash = cfg["api_hash"]
    phone = cfg.get("phone") or input("Please enter your phone: ").strip()

    client = TelegramClient(str(session_path), api_id, api_hash)
    client.connect()

    if client.is_user_authorized():
        print("[telegram] already authorized")
        client.disconnect()
        return 0

    if not client.is_user_authorized():
        client.send_code_request(phone)
        code = input("Please enter the code you received: ").strip()
        try:
            client.sign_in(phone=phone, code=code)
        except SessionPasswordNeededError:
            password = getpass("2FA password: ")
            client.sign_in(password=password)

    print("[telegram] login successful")
    client.disconnect()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
