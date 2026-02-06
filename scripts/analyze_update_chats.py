#!/usr/bin/env python3
"""Analyze aggregated Telegram+WhatsApp JSONL and print a concise /update_chats summary.

Design goals:
- Portable: rules + state live inside this repo.
- Minimal noise: drop ack-only replies; monitoring: show only important domains, severity>=warning, and never show clears.
- WhatsApp: if chat_title is empty, map from data/whatsapp_chats.txt (jid -> title) and cache in state.

Input JSONL format: records like those produced into /tmp/clawdbot_telegram.jsonl
("source" can be telegram/whatsapp; message_id may be non-numeric for WhatsApp).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

try:
    import yaml  # type: ignore
except Exception as e:
    print(f"Missing dependency: pyyaml ({e})", file=sys.stderr)
    raise


@dataclass
class Rules:
    ack_noise_regexes: list[str]
    monitoring_dump_prefixes: list[str]
    monitoring_dump_substrings: list[str]
    monitoring_clear_regex: str
    monitoring_severity_regex: str
    monitoring_domain_keywords: list[str]
    monitoring_ignore_substrings: list[str]
    wa_sender_map: dict[str, str]
    whatsapp_chats_file: str
    state_file: str


def load_yaml(path: Path) -> dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def resolve_relative(base: Path, value: str) -> Path:
    p = Path(value)
    return p if p.is_absolute() else (base / p)


def load_rules(path: Path) -> Rules:
    d = load_yaml(path)
    return Rules(
        ack_noise_regexes=list(d.get("ack_noise_regexes") or []),
        monitoring_dump_prefixes=list(d.get("monitoring_dump_prefixes") or []),
        monitoring_dump_substrings=list(d.get("monitoring_dump_substrings") or []),
        monitoring_clear_regex=str(d.get("monitoring_clear_regex") or ""),
        monitoring_severity_regex=str(d.get("monitoring_severity_regex") or ""),
        monitoring_domain_keywords=list(d.get("monitoring_domain_keywords") or []),
        monitoring_ignore_substrings=[s.lower() for s in (d.get("monitoring_ignore_substrings") or [])],
        wa_sender_map={str(k): str(v) for k, v in (d.get("wa_sender_map") or {}).items()},
        whatsapp_chats_file=str(d.get("whatsapp_chats_file") or "data/whatsapp_chats.txt"),
        state_file=str(d.get("state_file") or "data/update_chats_state.json"),
    )


def load_state(path: Path) -> dict[str, Any]:
    try:
        with path.open("r", encoding="utf-8") as f:
            return json.load(f) or {}
    except FileNotFoundError:
        return {}


def save_state(path: Path, state: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    tmp.replace(path)


def load_whatsapp_map(path: Path) -> dict[str, str]:
    """Parse whatsapp_chats.txt: jid\t<type>\t<title>"""
    m: dict[str, str] = {}
    try:
        with path.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.rstrip("\n")
                if "\t" not in line:
                    continue
                parts = line.split("\t")
                if len(parts) < 3:
                    continue
                jid = parts[0].strip()
                title = parts[2].strip()
                if jid and title:
                    m[jid] = title
    except FileNotFoundError:
        pass
    return m


def text_compact(s: str, n: int = 240) -> str:
    s = (s or "").strip().replace("\n", " ")
    s = re.sub(r"\s+", " ", s)
    return s if len(s) <= n else (s[: n - 1] + "…")


def is_monitoring_dump(text: str, rules: Rules) -> bool:
    t = text or ""
    for p in rules.monitoring_dump_prefixes:
        if t.startswith(p):
            return True
    for sub in rules.monitoring_dump_substrings:
        if sub in t:
            return True
    return False


def is_ack_noise(text: str, ack_res: list[re.Pattern[str]]) -> bool:
    t = (text or "").strip()
    return any(r.match(t) for r in ack_res)


def is_clear(text: str, clear_re: re.Pattern[str] | None) -> bool:
    return bool(clear_re and clear_re.search(text or ""))


def is_severity(text: str, sev_re: re.Pattern[str] | None) -> bool:
    return bool(sev_re and sev_re.search(text or ""))


def domain_match(text: str, kws_lower: list[str]) -> bool:
    t = (text or "").lower()
    return any(k in t for k in kws_lower)


def ignored_monitoring(text: str, rules: Rules) -> bool:
    t = (text or "").lower()
    return any(sub in t for sub in rules.monitoring_ignore_substrings)


def key_of(msg: dict[str, Any]) -> tuple[str, str]:
    # Comparable across TG and WA; WA message_id can be hex.
    return (msg.get("date") or "", str(msg.get("message_id") or ""))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jsonl", required=True, help="Path to aggregated JSONL (TG+WA)")
    ap.add_argument("--rules", default="config.update_chats_rules.yaml", help="Path to rules YAML")
    ap.add_argument("--print-empty", action="store_true", help="Print an explicit 'no new messages' line")
    args = ap.parse_args()

    repo = Path(__file__).resolve().parents[1]
    rules_path = Path(args.rules)
    if not rules_path.is_absolute():
        rules_path = repo / rules_path
    rules = load_rules(rules_path)

    state_path = resolve_relative(repo, rules.state_file)
    wa_chats_path = resolve_relative(repo, rules.whatsapp_chats_file)

    state_existed = state_path.exists()
    state = load_state(state_path)
    state.setdefault("chat_last_key", {})
    state.setdefault("wa_chat_map", {})

    wa_map = load_whatsapp_map(wa_chats_path)
    # merge cache
    state["wa_chat_map"].update(wa_map)
    wa_map = state["wa_chat_map"]

    ack_res = [re.compile(p, re.I) for p in rules.ack_noise_regexes]
    clear_re = re.compile(rules.monitoring_clear_regex, re.I) if rules.monitoring_clear_regex else None
    sev_re = re.compile(rules.monitoring_severity_regex, re.I) if rules.monitoring_severity_regex else None
    domain_kws_lower = [k.lower() for k in rules.monitoring_domain_keywords]

    jsonl_path = Path(args.jsonl).expanduser()
    msgs: list[dict[str, Any]] = []
    with jsonl_path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                m = json.loads(line)
            except Exception:
                continue
            # fill WA titles
            if (m.get("source") or "").lower() == "whatsapp":
                if not m.get("chat_title"):
                    cid = str(m.get("chat_id") or "")
                    if cid in wa_map:
                        m["chat_title"] = wa_map[cid]
            msgs.append(m)

    # compute max key per chat for state updates
    max_key_by_chat: dict[str, tuple[str, str]] = {}
    for m in msgs:
        cid = str(m.get("chat_id"))
        k = key_of(m)
        if cid not in max_key_by_chat or k > max_key_by_chat[cid]:
            max_key_by_chat[cid] = k

    # First run bootstrap: if no state file yet, mark everything as seen and exit.
    # This makes a fresh install quiet by default; you can delete the state file to re-bootstrap.
    if not state_existed:
        for cid, k in max_key_by_chat.items():
            state["chat_last_key"][cid] = {"date": k[0], "message_id": k[1]}
        save_state(state_path, state)
        if args.print_empty:
            print("Новых сообщений нет. (инициализация состояния)")
        return 0

    new_monitor: list[dict[str, Any]] = []
    new_disc: list[dict[str, Any]] = []

    last_keys: dict[str, Any] = state["chat_last_key"]

    for m in msgs:
        cid = str(m.get("chat_id"))
        k = key_of(m)
        last = last_keys.get(cid, {"date": "", "message_id": ""})
        lastk = (last.get("date", ""), str(last.get("message_id", "")))
        if k <= lastk:
            continue

        if m.get("is_service"):
            continue

        text = m.get("text") or ""

        monitoring = False
        if is_monitoring_dump(text, rules):
            monitoring = True
        # Heuristic: treat known bots as monitoring too
        u = (m.get("sender_username") or "")
        if u.endswith("_bot") or u in {"e2tl_bot", "Business_group_mess_prod_bot", "something_bad_vc_bot"}:
            monitoring = True

        if monitoring:
            if not text:
                continue
            if ignored_monitoring(text, rules):
                continue
            if is_clear(text, clear_re):
                continue
            if not is_severity(text, sev_re):
                continue
            if not domain_match(text, domain_kws_lower):
                continue
            new_monitor.append(m)
        else:
            if text and is_ack_noise(text, ack_res):
                continue
            if not text and m.get("has_media"):
                continue
            new_disc.append(m)

    # update state last seen
    for cid, k in max_key_by_chat.items():
        last_keys[cid] = {"date": k[0], "message_id": k[1]}
    save_state(state_path, state)

    if not new_monitor and not new_disc:
        if args.print_empty:
            print("Новых сообщений нет.")
        return 0

    # Print concise grouped output
    if new_monitor:
        print("Автомониторинг (важное):")
        for m in sorted(new_monitor, key=lambda x: ((x.get("date") or ""), (x.get("chat_title") or ""))):
            chat = m.get("chat_title") or "(unknown chat)"
            dt = m.get("date") or ""
            print(f"- {chat} ({dt}): {text_compact(m.get('text') or '')}")

    if new_disc:
        if new_monitor:
            print("")
        print("Чаты (новое):")
        for m in sorted(new_disc, key=lambda x: ((x.get("chat_title") or ""), (x.get("date") or ""), str(x.get("message_id") or ""))):
            chat = m.get("chat_title") or "(unknown chat)"
            dt = m.get("date") or ""
            if (m.get("source") or "").lower() == "whatsapp":
                sid = str(m.get("sender_id") or "")
                who = rules.wa_sender_map.get(sid) or (m.get("sender_username") or sid)
            else:
                who = m.get("sender_username") or str(m.get("sender_id") or "")
            print(f"- {chat} ({dt}) {who}: {text_compact(m.get('text') or '')}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
