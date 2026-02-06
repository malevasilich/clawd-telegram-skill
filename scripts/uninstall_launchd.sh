#!/usr/bin/env bash
set -euo pipefail

PLIST_DST="$HOME/Library/LaunchAgents/malevasilich.whatsapp_telegram_listeners.plist"

launchctl bootout "gui/$(id -u)" "$PLIST_DST" 2>/dev/null || true
rm -f "$PLIST_DST"

echo "Uninstalled malevasilich.whatsapp_telegram_listeners"
