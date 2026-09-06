#!/usr/bin/env bash
# 67 — Monitor scaling: patch omarchy-hyprland-monitor-scaling so the
# right-corner scale widget and `Super+Plus/Minus` actually apply.
#
# The upstream script issues:
#
#   hyprctl eval "hl.monitor({ output = ..., scale = $new })"
#
# `hyprctl eval` is a no-op (exits 0 with no error) when Hyprland's config
# manager is plain text (hyprland.conf) instead of Lua. It only takes effect
# on the Lua-based upstream Omarchy config. The Debian port uses a plain
# hyprland.conf, so the click looks successful but the scale never changes.
#
# Fix: try `hyprctl keyword monitor` first (works on both Lua and plain
# configs), fall back to `hyprctl eval` for Lua-only hosts. The patch is
# idempotent — re-running on an already-patched script is a no-op.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
TARGET="$OMARCHY_PATH/bin/omarchy-hyprland-monitor-scaling"

[ -f "$TARGET" ] || die "not found: $TARGET (install Omarchy first)"

# Already patched?
if grep -q 'Debian port note: `hyprctl eval` requires the Lua config manager' "$TARGET"; then
  ok "omarchy-hyprland-monitor-scaling already patched"
  exit 0
fi

# Older line we are replacing — single line in set_scale.
OLD_LINE='hyprctl eval "hl.monitor({ output = \"$active_monitor\", mode = \"${width}x${height}@${refresh_rate}\", position = \"auto\", scale = $new_scale })" >/dev/null'

NEW_BLOCK=$(cat <<'EOF'
# Debian port note: `hyprctl eval` requires the Lua config manager and
  # silently no-ops on a plain hyprland.conf (it prints "eval is only
  # supported with the lua config manager" and returns 0 anyway). The
  # classic `keyword monitor` IPC dispatcher works on both Lua and plain
  # configs, so try that first and fall back to eval for Lua-only hosts.
  if ! hyprctl keyword monitor "${active_monitor},${width}x${height}@${refresh_rate},auto,${new_scale}" >/dev/null 2>&1; then
    hyprctl eval "hl.monitor({ output = \"$active_monitor\", mode = \"${width}x${height}@${refresh_rate}\", position = \"auto\", scale = $new_scale })" >/dev/null
  fi
EOF
)

if grep -qF "$OLD_LINE" "$TARGET"; then
  # Build a temp file with the replacement, then atomically swap.
  tmp="$(mktemp)"
  awk -v old="$OLD_LINE" -v repl="$NEW_BLOCK" '
    index($0, old) { print repl; next }
    { print }
  ' "$TARGET" >"$tmp"
  mv "$tmp" "$TARGET"
  chmod +x "$TARGET"
  ok "patched omarchy-hyprland-monitor-scaling (keyword monitor first, eval fallback)"
else
  warn "omarchy-hyprland-monitor-scaling did not contain the expected `hyprctl eval` line"
  warn "this script may be a newer/different version — review and patch manually"
fi

# Quick smoke test: report the focused monitor's scale so the user can
# verify the right-corner widget picks it up.
focused="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused==true) | .name' 2>/dev/null || true)"
scale="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused==true) | .scale' 2>/dev/null || true)"
if [ -n "$focused" ]; then
  ok "focused monitor: $focused @ scale $scale — open the right-corner monitor panel and try the scale presets"
fi