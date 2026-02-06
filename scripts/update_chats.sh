#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"
TMP="/tmp/clawdbot_telegram.jsonl"

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

# Refresh aggregated jsonl (TG+WA) into $TMP
"$ROOT/scripts/sync_and_analyze.sh" >/dev/null 2>&1 || "$ROOT/scripts/sync_and_analyze.sh"

# Analyze with portable rules+state
"$PY" "$ROOT/scripts/analyze_update_chats.py" \
  --jsonl "$TMP" \
  --rules "$ROOT/config.update_chats_rules.yaml" \
  --print-empty
