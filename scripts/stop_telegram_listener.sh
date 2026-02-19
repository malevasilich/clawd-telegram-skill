#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"
DISABLE_FILE="$ROOT/data/disable_telegram"

mkdir -p "$ROOT/data"

# Create disable marker
: > "$DISABLE_FILE"

echo "Telegram listener disabled (marker: $DISABLE_FILE)"

# Kill any running Telegram listener processes
TG_PIDS=$(pgrep -f "clawd-telegram-skill/scripts/telegram_listen\.py" || true)
if [ -n "$TG_PIDS" ]; then
  echo "Stopping Telegram listener PIDs: $TG_PIDS"
  kill $TG_PIDS 2>/dev/null || true
  sleep 2
  TG_PIDS=$(pgrep -f "clawd-telegram-skill/scripts/telegram_listen\.py" || true)
  if [ -n "$TG_PIDS" ]; then
    echo "Force-killing remaining Telegram listener PIDs: $TG_PIDS"
    kill -9 $TG_PIDS 2>/dev/null || true
  fi
fi

# Restart launchd service if installed, so it won't re-spawn Telegram
"$ROOT/scripts/restart_launchd.sh" || true

