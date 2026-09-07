#!/usr/bin/env bash
# 73 — install wpaperd + user service, disable hyprpaper.
# ------------------------------------------------------------------
# wpaperd is a Wayland wallpaper daemon with native folder rotation,
# the closest equivalent to budgie-wallstreet for Hyprland/Omarchy.
# Debian trixie main does not carry it; we install via cargo (stripping any
# dead proxy so the build is not held hostage by a stale LAN PAC) until
# repo.freelamp.com carries the .deb built by
# packaging/rust-crate-deb/build.sh.
# ------------------------------------------------------------------
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"

log "73 — wpaperd rotation"

CARGO_BIN="$HOME/.cargo/bin/cargo"
[[ -x "$CARGO_BIN" ]] || die "cargo not found at $CARGO_BIN; install rustup first"

install_one() {
  local crate="$1"
  if command -v "$crate" >/dev/null 2>&1; then
    log "  $crate already present: $(command -v "$crate")"
    return
  fi
  log "  cargo install $crate --locked (proxy stripped, NO_PROXY=*)"
  # Cargo/libproxy honour the HTTP(S)_PROXY env and may also hand back a
  # proxy URL from an auto-detected PAC (e.g. a dead wpad.lan). Stripping
  # every proxy var and forcing NO_PROXY=* makes the build go straight to
  # the registry regardless of the surrounding network. Works for everyone.
  env -u http_proxy -u https_proxy -u all_proxy \
    -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
    NO_PROXY='*' HTTPS_PROXY='' HTTP_PROXY='' \
    "$CARGO_BIN" install "$crate" --locked
}

install_one wpaperd
install_one wpaperctl

# Drop the binary on PATH for systemd-user-service resolution.
mkdir -p "$HOME/.local/bin"
ln -sf "$HOME/.cargo/bin/wpaperd"  "$HOME/.local/bin/wpaperd"
ln -sf "$HOME/.cargo/bin/wpaperctl" "$HOME/.local/bin/wpaperctl"

# XDG-Autostart .desktop (matches budgie-wallstreet `app-wallstreet\x2dautostart@autostart.service`)
# We DO NOT hand-write ~/.config/systemd/user/wpaperd.service — the
# systemd-xdg-autostart-generator(8) takes care of that. Putting a
# wpaperd.desktop in ~/.config/autostart/ makes systemd mint
#   app-wpaperd\x2dautostart@autostart.service
# at every user session start, with the same anatomy as ghostty,
# blueman-applet, krita etc. This keeps the systemd tree clean and
# gives us X-MATE-AutoRestart / X-GNOME-AutoRestart semantics for free.
AUTOSTART_DIR="$HOME/.config/autostart"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/wpaperd-autostart.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=wpaperd
GenericName=Wayland Wallpaper Daemon
Comment=Rotates background images per output (declared in ~/.config/wpaperd/wallpaper.toml)
Exec=$HOME/.local/bin/wpaperd
Terminal=false
NoDisplay=true
X-MATE-AutoRestart=true
X-GNOME-AutoRestart=true
Categories=Utility;
DESKTOP
log "  wrote $AUTOSTART_DIR/wpaperd-autostart.desktop (generator → app-wpaperd\\x2dautostart@autostart.service)"

# Comment out hyprpaper exec-once — wpaperd owns the wallpaper slot.
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
if [[ -f "$HYPR_CONF" ]] && grep -q '^exec-once = hyprpaper' "$HYPR_CONF"; then
  sed -i 's|^exec-once = hyprpaper|# & omarchy: wpaperd takes over wallpaper slot|' "$HYPR_CONF"
  log "  disabled hyprpaper in $HYPR_CONF"
fi

# The wallpaper directory — single source of truth. The installer never
# fetches images (no Bing timer, no proxy hacks): it only makes sure the
# directory exists and points wpaperd at it. Drop your own files (or
# symlink a folder of them) in here and the daemon rotates them.
#
# Optional per-workspace pools: if you want a *different* image per
# workspace, create `ws1/ ws2/ …` sub-directories here and fill each.
# The switcher (step 74) uses `wsN/` when it exists, otherwise falls
# back to this flat directory. Plain users can ignore the sub-directories
# and just drop images at the top level.
WP_DIR="$HOME/Pictures/wallpapers"
mkdir -p "$WP_DIR"

# First run convenience: if the dir is still empty, symlink a few stock
# Debian backgrounds so there is something to look at. No network, no
# third-party source — just /usr/share/backgrounds shipped with the OS.
if ! find "$WP_DIR" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \
     -o -iname '*.png' -o -iname '*.webp' \) -print -quit 2>/dev/null | grep -q .; then
  copied=0
  shopt -s nullglob nocaseglob
  for f in /usr/share/backgrounds/*.{jpg,jpeg,png}; do
    [[ -f "$f" ]] || continue
    ln -sf "$f" "$WP_DIR/$(basename "$f")"
    copied=$((copied+1))
    [[ $copied -ge 8 ]] && break
  done
  shopt -u nullglob nocaseglob
  if [[ $copied -gt 0 ]]; then
    log "  seeded empty $WP_DIR with $copied symlinks from /usr/share/backgrounds"
  else
    info "  $WP_DIR is empty and no stock backgrounds were found —"
    info "  drop your own images in and they will rotate on the next reload."
  fi
fi

POOL="$WP_DIR"

# Generic wallpaper.toml. Section names are real monitor names (run
# `hyprctl monitors -j` to list). We only write `[default]` + `[any]`,
# both pointing at the single user directory — wpaperd applies them to
# whatever outputs actually exist, so this is correct on ANY machine
# (single screen, laptop, multi-monitor). No monitor-specific block is
# baked in; the per-workspace switcher (step 74) adds/rewrites one at
# runtime using the auto-detected active output.
if [[ ! -f "$HOME/.config/wpaperd/wallpaper.toml" ]]; then
  mkdir -p "$HOME/.config/wpaperd"
  cat > "$HOME/.config/wpaperd/wallpaper.toml" <<TOML
# wpaperd — generated by omarchy-on-debian (steps/73 + 74).
# Put your own images in $POOL — nothing is fetched for you.
# Monitor-specific [<name>] blocks are added at runtime by the
# per-workspace switcher (bin/wpaperd-ws-switch.py); do not hand-edit.

[default]
duration        = "5m"
mode            = "fit"
sorting         = "random"
transition_time = 1000

[any]
path = "$POOL"
TOML
  log "  wrote generic $HOME/.config/wpaperd/wallpaper.toml → $POOL"
fi

# Optional: Super+Shift+W → next, Super+Shift+Ctrl+W → previous.
# Omarchy upstream doesn't ship these; we add them as a QoL.
if [[ -f "$HYPR_CONF" ]] && ! grep -q "omarchy-wallpaper-rotate next" "$HYPR_CONF"; then
  cat >> "$HYPR_CONF" <<'BIND'

# --- omarchy-on-debian: wpaperd rotation keybinds ---
bind = $mainMod SHIFT, W, exec, omarchy-wallpaper-rotate next
bind = $mainMod SHIFT CTRL, W, exec, omarchy-wallpaper-rotate prev
BIND
  log "  added Super+Shift+W / Super+Shift+Ctrl+W binds in $HYPR_CONF"
fi

log "  generator creates app-wpaperd\\x2dautostart@autostart.service at every user session start"
log "  cycle manually: omarchy-wallpaper-rotate next / prev / pause / status"
log "  keybinds: Super+Shift+W = next, Super+Shift+Ctrl+W = prev"
