#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"
CFG="$ROOT/config.yaml"
OUT_JSONL="$ROOT/data/telegram_messages.jsonl"
DISABLE_TELEGRAM=0
if [ -f "$ROOT/data/disable_telegram" ] || [ "${TELEGRAM_DISABLED:-0}" = "1" ]; then
  DISABLE_TELEGRAM=1
fi

# Threshold for "stale" output (seconds)
STALE_SECS="${STALE_SECS:-900}"   # 15 minutes

RESTART=0
QUIET=0
STRICT_STALE=0
KILL_EXTRAS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --restart) RESTART=1 ;;
    --quiet) QUIET=1 ;;
    --strict-stale) STRICT_STALE=1 ;;
    --kill-extras) KILL_EXTRAS=1 ;;
    --stale-secs) STALE_SECS="$2"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

say() {
  if [ "$QUIET" -eq 0 ]; then
    echo "$@"
  fi
}

# Prefer pyenv python if available
if [ -d "$HOME/.pyenv/shims" ]; then
  export PATH="$HOME/.pyenv/shims:$PATH"
fi

# Find running listeners (use pgrep for safety)
TG_PIDS=$(pgrep -f "clawd-telegram-skill/scripts/telegram_listen\\.py" || true)
WA_PIDS=$(pgrep -f "clawd-telegram-skill/scripts/whatsapp_listen\\.js" || true)
TG_PID=$(echo "$TG_PIDS" | head -n 1 || true)
WA_PID=$(echo "$WA_PIDS" | head -n 1 || true)

healthy=1

if [ "$DISABLE_TELEGRAM" -eq 1 ]; then
  say "[OK] Telegram listener disabled"
else
  if [ -z "$TG_PID" ]; then
    say "[FAIL] Telegram listener is not running"
    healthy=0
  else
    say "[OK] Telegram listener running (PID $TG_PID)"
    if [ "$(echo "$TG_PIDS" | wc -l | tr -d ' ')" -gt 1 ]; then
      say "[WARN] Multiple Telegram listeners detected: $TG_PIDS"
      if [ "$KILL_EXTRAS" -eq 1 ]; then
        extras=$(echo "$TG_PIDS" | tail -n +2)
        say "[ACTION] Killing extra Telegram listeners: $extras"
        kill $extras 2>/dev/null || true
      fi
    fi
  fi
fi

if [ -z "$WA_PID" ]; then
  say "[FAIL] WhatsApp listener is not running"
  healthy=0
else
  say "[OK] WhatsApp listener running (PID $WA_PID)"
  if [ "$(echo "$WA_PIDS" | wc -l | tr -d ' ')" -gt 1 ]; then
    say "[WARN] Multiple WhatsApp listeners detected: $WA_PIDS"
    if [ "$KILL_EXTRAS" -eq 1 ]; then
      extras=$(echo "$WA_PIDS" | tail -n +2)
      say "[ACTION] Killing extra WhatsApp listeners: $extras"
      kill $extras 2>/dev/null || true
    fi
  fi
fi

# Staleness check: output JSONL updated recently?
# NOTE: If no one writes new messages, JSONL won't change. So by default this is only a warning.
if [ -f "$OUT_JSONL" ]; then
  now=$(date +%s)
  mtime=$(stat -f %m "$OUT_JSONL")
  age=$(( now - mtime ))
  if [ "$age" -gt "$STALE_SECS" ]; then
    say "[WARN] Output JSONL hasn't changed for ${age}s (> ${STALE_SECS}s): $OUT_JSONL"
    if [ "$STRICT_STALE" -eq 1 ]; then
      healthy=0
    fi
  else
    say "[OK] Output JSONL updated recently (age ${age}s)"
  fi
else
  say "[WARN] Output JSONL not found yet: $OUT_JSONL"
fi

if [ "$healthy" -eq 1 ]; then
  exit 0
fi

if [ "$RESTART" -eq 1 ]; then
  say "[ACTION] Restarting listeners via start_listeners.sh"
  # Best-effort stop
  if [ -n "$TG_PID" ]; then kill "$TG_PID" 2>/dev/null || true; fi
  if [ -n "$WA_PID" ]; then kill "$WA_PID" 2>/dev/null || true; fi
  sleep 1
  # Recheck to avoid duplicate starts
  TG_PID=$(pgrep -f "clawd-telegram-skill/scripts/telegram_listen\\.py" | head -n 1 || true)
  WA_PID=$(pgrep -f "clawd-telegram-skill/scripts/whatsapp_listen\\.js" | head -n 1 || true)
  if [ -n "$TG_PID" ] || [ -n "$WA_PID" ]; then
    say "[SKIP] Listener still running after kill attempt; not starting a duplicate."
    exit 1
  fi
  cd "$ROOT"
  LISTENER_LOG="${LISTENER_LOG:-quiet}" "$ROOT/scripts/start_listeners.sh" >/dev/null 2>&1 &
  disown || true
  say "[ACTION] Start command issued"
fi

exit 1
