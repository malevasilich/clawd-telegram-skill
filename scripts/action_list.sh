#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/mv/Dropbox/dev/python/clawd-telegram-skill"
JSONL="$ROOT/data/telegram_messages.jsonl"
RULES="$ROOT/config.update_chats_rules.yaml"

# Default window: today (local). You can override with --since-minutes N
SINCE_MINUTES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --since-minutes) SINCE_MINUTES="$2"; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

# Prefer pyenv python if available
if [ -d "$HOME/.pyenv/shims" ]; then
  export PATH="$HOME/.pyenv/shims:$PATH"
fi

python3 - <<'PY'
import json, re
from json import JSONDecoder
from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo

JSONL = r"/Users/mv/Dropbox/dev/python/clawd-telegram-skill/data/telegram_messages.jsonl"
RULES = r"/Users/mv/Dropbox/dev/python/clawd-telegram-skill/config.update_chats_rules.yaml"
SINCE_MINUTES = None

# Read SINCE_MINUTES from env injected by bash (optional)
import os
if os.environ.get('SINCE_MINUTES'):
    try:
        SINCE_MINUTES = int(os.environ['SINCE_MINUTES'])
    except Exception:
        SINCE_MINUTES = None

local = ZoneInfo('Asia/Almaty')

dec = JSONDecoder()

def parse_many(s: str):
    # File sometimes has multiple JSON objects per line, separated by spaces and literal "\\n" sequences.
    s = s.replace('\\n', '\n')
    objs = []
    i = 0
    n = len(s)
    while i < n:
        while i < n and s[i].isspace():
            i += 1
        if i >= n:
            break
        try:
            obj, j = dec.raw_decode(s, i)
        except Exception:
            i += 1
            continue
        if isinstance(obj, dict):
            objs.append(obj)
        i = j
    return objs

def parse_dt(s):
    if not s:
        return None
    try:
        if s.endswith('Z'):
            s = s[:-1] + '+00:00'
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except Exception:
        return None

# Load wa sender map for nicer output
wa_sender_map = {}
try:
    import yaml
    d = yaml.safe_load(open(RULES, 'r', encoding='utf-8')) or {}
    wa_sender_map = {str(k): str(v) for k, v in (d.get('wa_sender_map') or {}).items()}
except Exception:
    pass

# time window
now_local = datetime.now(local)
if SINCE_MINUTES:
    start_local = now_local - timedelta(minutes=SINCE_MINUTES)
else:
    start_local = datetime(now_local.year, now_local.month, now_local.day, 0, 0, 0, tzinfo=local)

# heuristics for "action required"
ACTION_PATTERNS = [
    r'\bнужно\b', r'\bсрочно\b', r'\bпрошу\b', r'\bждем\b', r'\bждём\b',
    r'\bсоглас(овать|уйте|уйте)\b', r'\bподпиш(и|ите)\b', r'\bпроверь(те)?\b',
    r'\bне могу\b', r'\bне можем\b', r'\bне работает\b', r'\bнедоступ\b',
    r'\bошибк', r'\bпроблем', r'\bпадает\b', r'\battack\b', r'\bddos\b',
    r'\bjira\b', r'DITIUSP-\d+', r'\bzoom\b',
]
act_re = re.compile('|'.join(ACTION_PATTERNS), re.I)

items = []
with open(JSONL, 'r', encoding='utf-8') as f:
    for line in f:
        if not line.strip():
            continue
        for rec in parse_many(line):
            dt = parse_dt(rec.get('date'))
            if not dt:
                continue
            dt_local = dt.astimezone(local)
            if dt_local < start_local:
                continue
            text = (rec.get('text') or '').strip()
            if not text:
                continue
            if not act_re.search(text):
                continue
            chat = rec.get('chat_title') or str(rec.get('chat_id'))
            who = rec.get('sender_username') or str(rec.get('sender_id') or '')
            if (rec.get('source') or '').lower() == 'whatsapp':
                who = wa_sender_map.get(who) or who
            txt = re.sub(r'\s+', ' ', text.replace('\n', ' '))
            if len(txt) > 260:
                txt = txt[:259] + '…'
            items.append((dt_local, chat, who, txt))

items.sort(key=lambda x: x[0])

print(f"/action_list окно: {start_local:%Y-%m-%d %H:%M} → {now_local:%Y-%m-%d %H:%M} (Алматы)")
if not items:
    print('Действий не найдено.')
    raise SystemExit(0)

# Group by chat
from collections import defaultdict
by = defaultdict(list)
for dt, chat, who, txt in items:
    by[chat].append((dt, who, txt))

for chat in sorted(by.keys(), key=lambda x: x.lower()):
    print(f"\n{chat}:")
    for dt, who, txt in by[chat][-10:]:
        print(f"- {dt:%H:%M} {who}: {txt}")
PY
