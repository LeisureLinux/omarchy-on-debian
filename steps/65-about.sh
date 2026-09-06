#!/usr/bin/env bash
# 65 — About (fastfetch TUI): config, branding logo, terminal-resolution glue.
# The menu's About entry runs omarchy-launch-about, which needs:
#   1. xdg-terminal-exec resolving to a terminal whose .desktop carries
#      X-TerminalArgAppId (kitty does, Debian's foot.desktop does not) —
#      without it the window's class stays "foot"/"kitty" and the
#      org.omarchy.about float/size rules never match.
#   2. /etc/fastfetch/config.jsonc — the Omarchy layout. A config in
#      ~/.config/fastfetch shadows it AND makes omarchy-launch-about skip
#      its window-fit and logo-sheen code paths (custom_fastfetch_config).
#   3. The About logo: ~/.local/share/omarchy/icon.txt, copied to
#      ~/.config/omarchy/branding/about.txt on first run.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

REPO="$(pwd)"
OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
need_sudo() { command -v sudo >/dev/null && echo sudo || echo; }
SUDO="$(need_sudo)"
[ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ] && die "need root or sudo for /etc/fastfetch"

# --- 1) terminal preference list (kitty first: X-TerminalArgAppId support)
run cp "$REPO/dotfiles/hyprland-xdg-terminals.list" "$HOME/.config/hyprland-xdg-terminals.list"
# The resolver caches its pick; the hash covers the list files, so no manual
# cache clearing is needed after this.

# --- 2) user-level kitty.desktop (ibus input-method variant) often shadows
#        the system one without the X-Terminal* keys — append them.
KITTY_DESKTOP="$HOME/.local/share/applications/kitty.desktop"
if [ -f "$KITTY_DESKTOP" ] && ! grep -q "X-TerminalArgAppId" "$KITTY_DESKTOP"; then
  run tee -a "$KITTY_DESKTOP" >/dev/null <<'KEYS'
X-TerminalArgExec=--
X-TerminalArgTitle=--title
X-TerminalArgAppId=--class
X-TerminalArgDir=--working-directory
X-TerminalArgHold=--hold
KEYS
  ok "added X-Terminal* keys to $KITTY_DESKTOP"
fi

# --- 3) Omarchy fastfetch layout. /etc/fastfetch is the right home: a
#        ~/.config/fastfetch/config.jsonc (any content) would shadow it and
#        silently disable the About fit + sheen.
if [ ! -f /etc/fastfetch/config.jsonc ]; then
  run $SUDO mkdir -p /etc/fastfetch
  run $SUDO cp "$REPO/dotfiles/fastfetch-config.jsonc" /etc/fastfetch/config.jsonc
  ok "/etc/fastfetch/config.jsonc installed"
else
  ok "/etc/fastfetch/config.jsonc already present"
fi
if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
  warn "~/.config/fastfetch/config.jsonc exists — it shadows /etc and disables the About auto-fit."
  warn "move it aside if About renders small: mv ~/.config/fastfetch/config.jsonc ~/.config/fastfetch/config.jsonc.bak"
fi

# --- 4) About logo: default Omarchy icon + the branding copy it is served from
run cp "$REPO/dotfiles/about-icon.txt" "$OMARCHY_PATH/icon.txt"
run mkdir -p "$HOME/.config/omarchy/branding"
[ -f "$HOME/.config/omarchy/branding/about.txt" ] ||
  run cp "$REPO/dotfiles/about-icon.txt" "$HOME/.config/omarchy/branding/about.txt"

ok "About ready — test with: omarchy-launch-about"
