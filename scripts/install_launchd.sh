#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run with sudo. Run as your user to install LaunchAgents." >&2
  exit 1
fi

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"
PLIST_SRC="$ROOT/launchd/malevasilich.whatsapp.telegram.listeners.plist"
PLIST_DST="$HOME/Library/LaunchAgents/malevasilich.whatsapp.telegram.listeners.plist"

if [ "${1:-}" = "--on-demand" ]; then
  PLIST_SRC="$ROOT/launchd/malevasilich.whatsapp.telegram.listeners.ondemand.plist"
fi

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$ROOT/logs"

cp "$PLIST_SRC" "$PLIST_DST"

# Enable first to clear any disabled override
launchctl enable "gui/$(id -u)/malevasilich.whatsapp.telegram.listeners" 2>/dev/null || true
launchctl bootout "gui/$(id -u)" "$PLIST_DST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl kickstart -k "gui/$(id -u)/malevasilich.whatsapp.telegram.listeners"

echo "Installed and started malevasilich.whatsapp.telegram.listeners"
