#!/usr/bin/env bash
set -euo pipefail

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run with sudo. Run as your user to manage LaunchAgents." >&2
  exit 1
fi

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"
LOG_OUT="$ROOT/logs/listeners.out.log"
LOG_ERR="$ROOT/logs/listeners.err.log"

"$ROOT/scripts/stop_launchd.sh" || true
sleep 1

: > "$LOG_OUT"
: > "$LOG_ERR"

"$ROOT/scripts/start_launchd.sh"
