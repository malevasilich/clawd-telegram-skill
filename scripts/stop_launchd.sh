#!/usr/bin/env bash
set -euo pipefail

LABEL="malevasilich.whatsapp_telegram_listeners"
launchctl stop "gui/$(id -u)/$LABEL"
