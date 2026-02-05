#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"
TMP="/tmp/clawdbot_telegram.jsonl"

python "$ROOT/scripts/query_telegram.py" \
  --config "$ROOT/config.yaml" \
  --since-days 1 \
  --latest \
  --limit 500 \
  > "$TMP"

clawdbot agent --local --agent main --message \
"/chats_update"
#"Проанализируй файл $TMP. \
# отфильтруй повторящиеся похожие сообщение мониторинга, оставив только нетипичные и аномалии. \
# проанализируй их и сделай сводку, оставив только важное, не нужно делать свод по каждому чату "
