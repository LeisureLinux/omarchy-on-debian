#!/usr/bin/env bash
# 60 — Hyprland: autostart, menu key, minimised-window workspace, sender-friendly binds.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

CONF="${HYPR_CONF:-$HOME/.config/hypr/hyprland.conf}"
[ -f "$CONF" ] || { warn "$CONF not found — skipping (set HYPR_CONF)"; exit 0; }

MARKER="# >>> omarchy-on-debian"
BLOCK="$MARKER
# CRITICAL: Hyprland's own PATH does NOT include ~/.local/share/omarchy/bin
# (where every omarchy-* script lives), so any bind calling omarchy-menu /
# omarchy-shell / omarchy-capture-* / omarchy-hyprland-* silently no-ops.
# Prepend it here so the official keybindings resolve.
env = PATH, \$HOME/.local/share/omarchy/bin:\$HOME/.local/bin:\$PATH

# Omarchy shell (Quickshell) root. omarchy-menu / omarchy-shell use `qs ipc -p
# \$OMARCHY_PATH/shell`, so without this every menu/panel bind fails with
# "OMARCHY_PATH is not set". Must live on Hyprland's own env — exports from the
# exec-once omarchy-port do NOT reach Hyprland-spawned child processes.
env = OMARCHY_PATH, \$HOME/.local/share/omarchy

# Autostart the shell (replaces waybar/mako — comment those out yourself)
exec-once = \$HOME/.local/bin/omarchy-port

# Menu / launcher
bind = \$mainMod, space, exec, \$HOME/.local/bin/omarchy-menu-toggle
bind = \$mainMod ALT, T, exec, \$HOME/.local/share/omarchy/bin/omarchy-menu toggle theme

# About (fastfetch) window — class comes from xdg-terminal-exec passing
# kitty's --class; without these the TUI opens tiled and clipped.
windowrule = match:class ^(org\\.omarchy\\.about)\$, float on
windowrule = match:class ^(org\\.omarchy\\.about)\$, center on
windowrule = match:class ^(org\\.omarchy\\.about)\$, size 1100 580

# Hyprland has no minimize dispatcher: park windows on a special workspace
bind = \$mainMod, M, movetoworkspacesilent, special:minimized
bind = \$mainMod, R, togglespecialworkspace, minimized
bind = \$mainMod CTRL, X, exit,
# <<< omarchy-on-debian"

append_once "$CONF" "$MARKER" "$BLOCK"

# Autostart conflicts: waybar and mako both claim the bar / notifications.
if grep -qE "exec-once *= *[^#]*(waybar|mako)" "$CONF"; then
  warn "waybar/mako still in autostart — comment them out to avoid two bars"
fi

if command -v hyprctl >/dev/null && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  run hyprctl reload
  ok "hyprctl reload"
else
  info "not inside Hyprland — binds apply at next login"
fi
