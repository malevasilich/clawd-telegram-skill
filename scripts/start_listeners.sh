#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"

# Prefer pyenv python if available (keeps deps consistent with other scripts)
if [ -d "$HOME/.pyenv/shims" ]; then
  export PATH="$HOME/.pyenv/shims:$PATH"
fi

# Load local env if present (API keys etc)
if [ -f "$ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1090
  source "$ROOT/.env"
  set +a
fi

# Set LISTENER_LOG=quiet|verbose to control logging for both listeners
LISTENER_LOG="${LISTENER_LOG:-}"

# Ensure node/python are resolvable in launchd environment
if [ -d "$HOME/.pyenv/shims" ]; then
  export PATH="$HOME/.pyenv/shims:$PATH"
fi
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

terminated=0
cleanup() {
  terminated=1
  if kill -0 "$TG_PID" 2>/dev/null; then
    echo "Stopping Telegram listener (PID $TG_PID)..."
    kill "$TG_PID"
    wait "$TG_PID" 2>/dev/null || true
  fi
  if kill -0 "$WA_PID" 2>/dev/null; then
    echo "Stopping WhatsApp listener (PID $WA_PID)..."
    kill "$WA_PID"
    wait "$WA_PID" 2>/dev/null || true
  fi
}

trap cleanup INT TERM

# Pick node interpreter
if command -v node >/dev/null 2>&1; then
  NODE=node
elif [ -x "/opt/homebrew/bin/node" ]; then
  NODE="/opt/homebrew/bin/node"
elif [ -x "/usr/local/bin/node" ]; then
  NODE="/usr/local/bin/node"
else
  echo "node not found in PATH. Current PATH=$PATH" >&2
  exit 1
fi

# Start WhatsApp listener in background
LISTENER_LOG="$LISTENER_LOG" "$NODE" "$ROOT/scripts/whatsapp_listen.js" --config "$ROOT/config.yaml" &
WA_PID=$!

# Pick python interpreter
if command -v python >/dev/null 2>&1; then
  PY=python
elif command -v python3 >/dev/null 2>&1; then
  PY=python3
else
  echo "No python interpreter found" >&2
  exit 1
fi

# Start Telegram listener in background
LISTENER_LOG="$LISTENER_LOG" "$PY" "$ROOT/scripts/telegram_listen.py" --config "$ROOT/config.yaml" &
TG_PID=$!

echo "Telegram listener running (PID $TG_PID)."
echo "WhatsApp listener running (PID $WA_PID). Press Ctrl+C to stop."
while true; do
  # Optional health check
  if [ "${CHECK_EVERY_SECONDS:-0}" -gt 0 ]; then
    "$ROOT/scripts/check_listeners.sh" --quiet || {
      echo "Health check failed. Exiting so supervisor can restart." >&2
      exit 1
    }
    sleep "${CHECK_EVERY_SECONDS}"
  fi
  if ! kill -0 "$WA_PID" 2>/dev/null; then
    wait "$WA_PID" || WA_RC=$?
    if [ "${terminated}" -eq 1 ]; then
      exit 0
    fi
    echo "WhatsApp listener exited (code ${WA_RC:-0})" >&2
    kill "$TG_PID" 2>/dev/null || true
    wait "$TG_PID" 2>/dev/null || true
    exit 1
  fi
  if ! kill -0 "$TG_PID" 2>/dev/null; then
    wait "$TG_PID" || TG_RC=$?
    if [ "${terminated}" -eq 1 ]; then
      exit 0
    fi
    echo "Telegram listener exited (code ${TG_RC:-0})" >&2
    kill "$WA_PID" 2>/dev/null || true
    wait "$WA_PID" 2>/dev/null || true
    exit 1
  fi
  sleep 1
done
