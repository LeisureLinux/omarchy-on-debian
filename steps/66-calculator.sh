#!/usr/bin/env bash
# 66 — Calculator (omacalc): Debian port of Omarchy's floating calculator.
#
# Upstream ships `omacalc` as a standalone Qt/QML AUR package
# (github.com/omacom-io/omacalc) that the Hyprland bindings
# `SUPER+CTRL+Q` and `XF86Calculator` invoke. Debian has no AUR, so we:
#   1. apt-install `qalc` (the calculation engine omacalc wraps).
#   2. drop a rofi+qalc wrapper (bin/omacalc) into the Omarchy bin dir so the
#      official bindings resolve and open a floating calculator.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

REPO="$(pwd)"
OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
need_sudo() { command -v sudo >/dev/null && echo sudo || echo; }
SUDO="$(need_sudo)"

# --- 1) qalc engine ---
if command -v qalc >/dev/null 2>&1; then
  ok "qalc already installed ($(qalc --version 2>&1 | head -1))"
else
  info "installing qalc (apt)…"
  run $SUDO apt-get update -y
  run $SUDO apt-get install -y qalc
  ok "qalc installed"
fi

# --- 2) rofi is the UI frontend (needed by the wrapper) ---
# It is not in step 10's core deps, so a fresh install would otherwise get
# a calculator that can't open. Install it here so the feature actually works.
if command -v rofi >/dev/null 2>&1; then
  ok "rofi already installed ($(rofi -version 2>&1 | head -1))"
else
  info "installing rofi (apt)…"
  run $SUDO apt-get install -y rofi
  ok "rofi installed"
fi

# --- 3) deploy the wrapper into the Omarchy bin dir ---
mkdir -p "$OMARCHY_PATH/bin"
run cp "$REPO/bin/omacalc" "$OMARCHY_PATH/bin/omacalc"
run chmod +x "$OMARCHY_PATH/bin/omacalc"
ok "omacalc wrapper deployed to $OMARCHY_PATH/bin/omacalc"
ok "Calculator ready — test with: Super+Ctrl+Q (or the calculator key)"
