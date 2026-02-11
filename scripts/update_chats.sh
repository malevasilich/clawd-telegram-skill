#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"
SRC_JSONL="$ROOT/data/telegram_messages.jsonl"

cd "$ROOT"

# Prefer pyenv python if available
if [ -d "$HOME/.pyenv/shims" ]; then
  export PATH="$HOME/.pyenv/shims:$PATH"
fi

if command -v python >/dev/null 2>&1; then
  PY=python
elif command -v python3 >/dev/null 2>&1; then
  PY=python3
else
  echo "No python interpreter found" >&2
  exit 1
fi

# No /tmp snapshot: analyze the live aggregated store directly
"$PY" "$ROOT/scripts/analyze_update_chats.py" \
  --jsonl "$SRC_JSONL" \
  --rules "$ROOT/config.update_chats_rules.yaml" \
  --print-empty
