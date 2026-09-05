#!/usr/bin/env bash
# 30 — deploy the payload into ~/.local/share/omarchy and install the launcher shims.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

SRC="$(cat "$OMARCHY_WORK/.src-root" 2>/dev/null || echo "")"
[ -z "$SRC" ] && [ -n "${OMARCHY_SRC:-}" ] && SRC="$OMARCHY_SRC"
[ -z "$SRC" ] && SRC="$OMARCHY_WORK/src"
[ -d "$SRC/shell" ] || die "no source at $SRC — run step 20 first"

need_cmd rsync
run mkdir -p "$OMARCHY_HOME"

# shell/ is the Quickshell config; bin/ the 90+ omarchy-* helper scripts the
# QML shells out to; config/ themes/ default/ carry the theme + app defaults.
for d in shell bin config default themes; do
  [ -d "$SRC/$d" ] || { warn "skipping $d (not in source)"; continue; }
  run rsync -a --delete "$SRC/$d"/ "$OMARCHY_HOME/$d"/
  ok "deployed $d/"
done

# --- launcher + menu toggle: these are ours, not upstream's
install_file dotfiles/omarchy-port        "$HOME/.local/bin/omarchy-port"        0755
install_file dotfiles/omarchy-menu-toggle "$HOME/.local/bin/omarchy-menu-toggle" 0755

# --- uwsm shim: upstream wraps app launches in uwsm-app (Arch session manager).
#     Debian has no uwsm; without this shim every menu launch is a silent no-op.
install_file dotfiles/uwsm-app "$OMARCHY_HOME/bin/uwsm-app" 0755

# --- PATH for login shells. Menu actions run through `bash -lc`, which resets
#     PATH via /etc/profile; without this every omarchy-* command is not found.
PROFILE_MARKER="# omarchy-on-debian: PATH for login shells"
PROFILE_BLOCK="$PROFILE_MARKER
if [ -d \"\$HOME/.local/share/omarchy/bin\" ]; then
  export PATH=\"\$HOME/.local/share/omarchy/bin:\$PATH\"
fi"
for f in "$HOME/.profile" "$HOME/.bash_profile"; do
  [ -f "$f" ] || [ "$f" = "$HOME/.profile" ] || continue
  append_once "$f" "$PROFILE_MARKER" "$PROFILE_BLOCK"
done

# --- menu definition: forget this and Super+D opens an empty panel
# It ships inside default/omarchy/ and is normally read from there; a copy in
# ~/.config/omarchy/ is only needed if the payload layout moves it.
if [ -f "$SRC/default/omarchy/omarchy-menu.jsonc" ] && [ ! -f "$HOME/.config/omarchy/omarchy-menu.jsonc" ]; then
  info "menu definition present in payload (default/omarchy/omarchy-menu.jsonc)"
else
  [ -f "$HOME/.config/omarchy/omarchy-menu.jsonc" ] && ok "menu definition already installed" \
    || warn "omarchy-menu.jsonc not found — Super+D will open an empty panel"
fi

ok "deployment complete"
