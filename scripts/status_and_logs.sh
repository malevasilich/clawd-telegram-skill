#!/usr/bin/env bash
set -euo pipefail

LABEL="malevasilich.whatsapp_telegram_listeners"
LOG_OUT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill/logs/listeners.out.log"
LOG_ERR="/Users/mv/Dropbox/dev/python/clawd-telegram-skill/logs/listeners.err.log"
LINES="${LINES:-50}"

launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null || {
  echo "Service not loaded: $LABEL"
  exit 1
}

echo "--- stdout (last $LINES lines) ---"
if [ -f "$LOG_OUT" ]; then
  tail -n "$LINES" "$LOG_OUT"
else
  echo "(missing) $LOG_OUT"
fi

echo "--- stderr (last $LINES lines) ---"
if [ -f "$LOG_ERR" ]; then
  tail -n "$LINES" "$LOG_ERR"
else
  echo "(missing) $LOG_ERR"
fi
