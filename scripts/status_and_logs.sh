#!/usr/bin/env bash
set -euo pipefail

LABEL="malevasilich.whatsapp.telegram.listeners"
USER_ID="$(id -u)"
LOG_OUT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill/logs/listeners.out.log"
LOG_ERR="/Users/mv/Dropbox/dev/python/clawd-telegram-skill/logs/listeners.err.log"
LINES="${LINES:-50}"

if launchctl print "gui/$USER_ID" >/dev/null 2>&1; then
  DOMAIN_BASE="gui/$USER_ID"
else
  DOMAIN_BASE="user/$USER_ID"
fi
DOMAIN="$DOMAIN_BASE/$LABEL"

INFO=$(launchctl print "$DOMAIN" 2>/dev/null) || {
  echo "Service not loaded: $LABEL"
  exit 1
}

echo "$INFO" | grep -E "RunAtLoad|KeepAlive|state|path|program" || true

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
