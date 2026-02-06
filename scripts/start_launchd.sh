#!/usr/bin/env bash
set -euo pipefail

LABEL="malevasilich.whatsapp_telegram_listeners"
launchctl kickstart -k "gui/$(id -u)/$LABEL"
