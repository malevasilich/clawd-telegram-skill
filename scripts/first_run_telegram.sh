#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"

# Pick python
if command -v python >/dev/null 2>&1; then
  PY=python
elif command -v python3 >/dev/null 2>&1; then
  PY=python3
else
  echo "Python not found in PATH" >&2
  exit 1
fi

"$ROOT/scripts/telegram_login.py" --config "$ROOT/config.yaml"
