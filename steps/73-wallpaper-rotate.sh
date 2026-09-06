#!/usr/bin/env bash
# 73 — install wpaperd + user service, disable hyprpaper.
# ------------------------------------------------------------------
# wpaperd is a Wayland wallpaper daemon with native folder rotation,
# the closest equivalent to budgie-wallstreet for Hyprland/Omarchy.
# Debian trixie main does not carry it; we install via cargo (with
# the wpad.lan proxy stripped) until repo.freelamp.com carries the
# .deb built by packaging/rust-crate-deb/build.sh.
# ------------------------------------------------------------------
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"

log "73 — wpaperd rotation"

CARGO_BIN="$HOME/.cargo/bin/cargo"
[[ -x "$CARGO_BIN" ]] || die "cargo not found at $CARGO_BIN; install rustup first"

# Pin wpad.lan to localhost so cargo's libproxy auto-detect (which
# tries to fetch a PAC file from the wpad hostname) doesn't time out
# on every registry hit. /etc/hosts is world-writable on Debian
# trixie, so no sudo required. The commented line in /etc/hosts
# (192.168.222.115 wpad wpad.local wpad.lan) does NOT resolve — we
# need a real, un-commented entry to satisfy libproxy.
if ! grep -qE "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\s+.*\bwpad\.lan\b" /etc/hosts 2>/dev/null; then
  log "  pinning wpad.lan → 127.0.0.1 in /etc/hosts"
  printf "127.0.0.1 wpad.lan\n" >> /etc/hosts
fi

install_one() {
  local crate="$1"
  if command -v "$crate" >/dev/null 2>&1; then
    log "  $crate already present: $(command -v "$crate")"
    return
  fi
  log "  cargo install $crate --locked (proxy stripped + NO_PROXY=*)"
  # Two layered fixes for the wpad.lan dead-proxy hell:
  #   1. /etc/hosts pin (above) — libproxy stops trying to resolve
  #      wpad.lan via DNS.
  #   2. NO_PROXY=* + empty HTTPS_PROXY — reqwest/libproxy will still
  #      hand back a "wpad.lan:8888" proxy URL via PAC, but reqwest
  #      skips it because NO_PROXY matches everything.
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

# Seed the wallpaper dir + an example toml the first time.
WP_DIR="$HOME/Pictures/wallpapers"
if [[ ! -d "$WP_DIR" ]]; then
  mkdir -p "$WP_DIR"
  # Pull a few backgrounds from /usr/share/backgrounds if available.
  copied=0
  shopt -s nullglob nocaseglob
  for f in /usr/share/backgrounds/*.{jpg,jpeg,png}; do
    [[ -f "$f" ]] || continue
    ln -sf "$f" "$WP_DIR/$(basename "$f")"
    copied=$((copied+1))
    [[ $copied -ge 8 ]] && break
  done
  shopt -u nullglob nocaseglob
  log "  seeded $WP_DIR with $copied symlinks from /usr/share/backgrounds"
fi

# wpaperd 1.0.1 config quirks:
#   * filename MUST be `wallpaper.toml` (legacy; the binary's
#     place_config_file("wallpaper.toml") takes precedence over
#     place_config_file("config.toml")).
#   * section names are monitor names directly ([DP-4], [eDP-1]),
#     NOT [output.DP-4]. `output.` is an old 0.x syntax.
#   * no [socket] section — the socket path is hard-coded.
#   * valid fields: path, duration, apply-shadow, sorting, mode,
#     queue_size, transition_time. `transition_type` does NOT exist
#     in 1.0.1 (it is planned upstream but not yet released).
if [[ ! -f "$HOME/.config/wpaperd/wallpaper.toml" ]]; then
  mkdir -p "$HOME/.config/wpaperd"
  cat > "$HOME/.config/wpaperd/wallpaper.toml" <<TOML
# wpaperd 1.0.1 — generated by omarchy-on-debian/steps/73-wallpaper-rotate.sh
# Section names are monitor names. Run `hyprctl monitors -j` to list.
# Recognised fields: path, duration, apply-shadow, sorting, mode,
# queue_size, transition_time. `transition_type` is not a 1.0.1 field.

[default]
duration = "15m"
mode = "fit"
sorting = "random"
transition_time = 1000

[any]
path = "$WP_DIR"

[DP-4]
path = "$WP_DIR"

[eDP-1]
path = "$WP_DIR"
TOML
  log "  wrote $HOME/.config/wpaperd/wallpaper.toml"
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
