#!/usr/bin/env bash
set -euo pipefail

LABEL="malevasilich.whatsapp_telegram_listeners"
launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null || {
  echo "Service not loaded: $LABEL"
  exit 1
}
