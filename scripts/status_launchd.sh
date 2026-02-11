#!/usr/bin/env bash
set -euo pipefail

LABEL="malevasilich.whatsapp_telegram_listeners"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
NOW="$(date '+%Y-%m-%d %H:%M:%S %Z')"

if [ -t 1 ]; then
  GREEN="\033[0;32m"
  RED="\033[0;31m"
  YELLOW="\033[0;33m"
  NC="\033[0m"
else
  GREEN=""
  RED=""
  YELLOW=""
  NC=""
fi

INFO=$(launchctl print "gui/$(id -u)/$LABEL" 2>/dev/null) || {
  echo "${RED}[$NOW] Service not loaded: $LABEL${NC}"
  exit 1
}

state=$(echo "$INFO" | awk -F' = ' '/state =/ {print $2; exit}')
pid=$(echo "$INFO" | awk -F' = ' '/pid =/ {print $2; exit}')

read_plist_key() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$PLIST" 2>/dev/null || echo "unknown"
}

run_at_load="unknown"
keep_alive="unknown"
if [ -f "$PLIST" ]; then
  run_at_load=$(read_plist_key "RunAtLoad")
  keep_alive=$(read_plist_key "KeepAlive")
fi

status_color="$YELLOW"
if [ "$state" = "running" ]; then
  status_color="$GREEN"
elif [ "$state" = "not running" ]; then
  status_color="$RED"
fi

echo "${status_color}[$NOW] $LABEL state=${state} pid=${pid:-n/a}${NC}"
echo "RunAtLoad=${run_at_load} KeepAlive=${keep_alive}"
