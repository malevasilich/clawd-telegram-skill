#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run with sudo. Run as your user to manage LaunchAgents." >&2
  exit 1
fi

LABEL="malevasilich.whatsapp.telegram.listeners"
USER_ID="$(id -u)"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"

if launchctl print "gui/$USER_ID" >/dev/null 2>&1; then
  DOMAIN_BASE="gui/$USER_ID"
else
  DOMAIN_BASE="user/$USER_ID"
fi
DOMAIN="$DOMAIN_BASE/$LABEL"

# Stop and unload to prevent KeepAlive from restarting it
launchctl stop "$DOMAIN" 2>/dev/null || true
launchctl disable "$DOMAIN" 2>/dev/null || true
launchctl bootout "$DOMAIN_BASE" "$PLIST" 2>/dev/null || true

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
