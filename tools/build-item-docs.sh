#!/usr/bin/env bash
# Regenerate BOTH item references from items.js — the browsable page and the
# filterable workbook. Run after any items.js edit.
#
#   tools/build-item-docs.sh
#
# Step 1 reads items.js (the source of truth), classifies every item by the
# outcome it pays in, writes item-list.html and the machine-readable
# tools/items-export.json. Step 2 turns that export into item-list.xlsx, so
# the workbook's grouping is the page's grouping — one taxonomy, two files.
set -euo pipefail
cd "$(dirname "$0")/.."
node tools/build-item-list.mjs
python3 tools/build-item-workbook.py
echo "→ item-list.html · item-list.xlsx"
