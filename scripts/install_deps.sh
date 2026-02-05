#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python -m pip install --upgrade pip
python -m pip install -r "$ROOT_DIR/requirements.txt"

printf "Dependencies installed.\n"
