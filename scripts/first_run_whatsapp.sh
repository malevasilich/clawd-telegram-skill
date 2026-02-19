#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"

# Pick node
if command -v node >/dev/null 2>&1; then
  NODE=node
elif [ -x "/opt/homebrew/bin/node" ]; then
  NODE="/opt/homebrew/bin/node"
elif [ -x "/usr/local/bin/node" ]; then
  NODE="/usr/local/bin/node"
else
  echo "Node not found in PATH" >&2
  exit 1
fi

"$NODE" "$ROOT/scripts/whatsapp_login.js" --config "$ROOT/config.yaml"
