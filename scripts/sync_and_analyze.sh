#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"
TMP="/tmp/clawdbot_telegram.jsonl"

cd "$ROOT"

# Ensure we have a usable Python (pyenv shim preferred)
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

# Load local env if present (so this script works outside interactive shells)
if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ROOT/.env"
  set +a
fi

"$PY" "$ROOT/scripts/sync_telegram.py" --config "$ROOT/config.yaml"

"$PY" "$ROOT/scripts/query_telegram.py" \
  --config "$ROOT/config.yaml" \
  --since-days 1 \
  --latest \
  --limit 500 \
  > "$TMP"

# "$ROOT/scripts/analyze_latest.sh"