#!/usr/bin/env bash
set -euo pipefail

LABEL="malevasilich.whatsapp_telegram_listeners"
DOMAIN="gui/$(id -u)/$LABEL"

launchctl stop "$DOMAIN" 2>/dev/null || true

# Best-effort stop any stray listener processes
patterns=(
  "clawd-telegram-skill/scripts/start_listeners.sh"
  "clawd-telegram-skill/scripts/telegram_listen.py"
  "clawd-telegram-skill/scripts/whatsapp_listen.js"
)

for pat in "${patterns[@]}"; do
  pids=$(pgrep -f "$pat" || true)
  if [ -n "$pids" ]; then
    echo "Stopping processes matching: $pat"
    kill $pids 2>/dev/null || true
  fi
done

# Wait briefly, then force-kill if needed
sleep 2
for pat in "${patterns[@]}"; do
  pids=$(pgrep -f "$pat" || true)
  if [ -n "$pids" ]; then
    echo "Force-killing processes matching: $pat"
    kill -9 $pids 2>/dev/null || true
  fi
done
