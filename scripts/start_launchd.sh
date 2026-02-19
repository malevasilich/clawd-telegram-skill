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

launchctl enable "$DOMAIN" 2>/dev/null || true

if ! launchctl print "$DOMAIN" >/dev/null 2>&1; then
  if [ ! -f "$PLIST" ]; then
    echo "LaunchAgent plist not found: $PLIST" >&2
    exit 1
  fi
  if ! launchctl bootstrap "$DOMAIN_BASE" "$PLIST" 2>/dev/null; then
    # Fallback: try the other domain type
    if [ "$DOMAIN_BASE" = "gui/$USER_ID" ]; then
      DOMAIN_BASE="user/$USER_ID"
    else
      DOMAIN_BASE="gui/$USER_ID"
    fi
    DOMAIN="$DOMAIN_BASE/$LABEL"
    launchctl bootstrap "$DOMAIN_BASE" "$PLIST"
  fi
fi

launchctl enable "$DOMAIN" 2>/dev/null || true
launchctl kickstart -k "$DOMAIN"
