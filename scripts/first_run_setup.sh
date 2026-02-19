#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"

echo "This will run interactive logins for Telegram and WhatsApp in the foreground."

# Ensure deps are installed
if ! command -v python >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  echo "Python not found in PATH" >&2
  exit 1
fi
if ! command -v node >/dev/null 2>&1 && [ ! -x "/opt/homebrew/bin/node" ] && [ ! -x "/usr/local/bin/node" ]; then
  echo "Node not found in PATH" >&2
  exit 1
fi

# Pick python
if command -v python >/dev/null 2>&1; then
  PY=python
else
  PY=python3
fi

# Pick node
if command -v node >/dev/null 2>&1; then
  NODE=node
elif [ -x "/opt/homebrew/bin/node" ]; then
  NODE="/opt/homebrew/bin/node"
else
  NODE="/usr/local/bin/node"
fi

# Stop launchd service if running to avoid duplicates
"$ROOT/scripts/stop_launchd.sh" || true

echo ""
echo "Step 1/2: Telegram login"
LISTENER_LOG=verbose "$PY" "$ROOT/scripts/telegram_login.py" --config "$ROOT/config.yaml"

echo ""
echo "Step 2/2: WhatsApp login (QR will be shown)"
LISTENER_LOG=verbose "$NODE" "$ROOT/scripts/whatsapp_login.js" --config "$ROOT/config.yaml"

echo "\nDone. You can now start the service with:"
echo "  $ROOT/scripts/install_launchd_keepalive.sh"
