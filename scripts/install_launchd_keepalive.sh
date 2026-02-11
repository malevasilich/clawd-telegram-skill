#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"
PLIST_SRC="$ROOT/launchd/malevasilich.whatsapp_telegram_listeners.plist"
PLIST_DST="$HOME/Library/LaunchAgents/malevasilich.whatsapp_telegram_listeners.plist"

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$ROOT/logs"

cp "$PLIST_SRC" "$PLIST_DST"

launchctl bootout "gui/$(id -u)" "$PLIST_DST" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
launchctl enable "gui/$(id -u)/malevasilich.whatsapp_telegram_listeners"
launchctl kickstart -k "gui/$(id -u)/malevasilich.whatsapp_telegram_listeners"

echo "Installed keepalive service malevasilich.whatsapp_telegram_listeners"
