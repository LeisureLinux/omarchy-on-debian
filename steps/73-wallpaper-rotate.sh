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

# Detect the real Bing pool (XDG `backgrounds` dir, where
# `getBingImage.sh` driven by `bing-image.timer` drops its daily
# pulls). Falls back to Pictures/wallpapers only if it doesn't yet
# exist — first-run case before the user has set up their Bing timer.
if [[ -d "$HOME/.local/share/backgrounds" ]] \
   && ls "$HOME/.local/share/backgrounds/"*.jpg &>/dev/null; then
  POOL="$HOME/.local/share/backgrounds"
  log "  using XDG backgrounds pool ($POOL) for rotation"
else
  POOL="$WP_DIR"
  log "  using fallback pool ($POOL); XDG backgrounds missing"
fi

# wpaperd 1.0.1 config quirks (see README "Wallpaper rotation"):
#   * filename MUST be `wallpaper.toml` (legacy; the binary's
#     place_config_file("wallpaper.toml") runs before
#     place_config_file("config.toml")).
#   * section names are monitor names directly ([DP-4], [eDP-1]),
#     NOT [output.DP-4]. `output.` is an old 0.x syntax.
#   * no [socket] section — the socket path is hard-coded.
#   * valid fields: path, duration, apply-shadow, sorting, mode,
#     queue_size, transition_time. `transition_type` does NOT exist
#     in 1.0.1 (it is planned upstream but not yet released).
#
# Pool topology:
#   - any    → shared XDG pool (works for any monitor)
#   - eDP-1  → shared pool; cadenced at 5m (laptop feel)
#   - DP-4   → `widescreen/` sub-pool (16:9 / 21:9 picks); 10m cadence
#              (less head-turning on a big external)
mkdir -p "$POOL/widescreen"
if [[ ! -f "$HOME/.config/wpaperd/wallpaper.toml" ]]; then
  mkdir -p "$HOME/.config/wpaperd"
  cat > "$HOME/.config/wpaperd/wallpaper.toml" <<TOML
# wpaperd 1.0.1 — generated by omarchy-on-debian/steps/73-wallpaper-rotate.sh
# Section names are monitor names. Run \`hyprctl monitors -j\` to list.
# Recognised fields: path, duration, apply-shadow, sorting, mode,
# queue_size, transition_time. \`transition_type\` is not a 1.0.1 field.

[default]
duration  = "5m"
mode      = "fit"
sorting   = "random"
transition_time = 1000

[any]
path = "$POOL"

[eDP-1]
duration = "5m"
path = "$POOL"

[DP-4]
duration = "10m"
path = "$POOL/widescreen"
TOML
  log "  wrote $HOME/.config/wpaperd/wallpaper.toml (any/eDP-1 share $POOL, DP-4 → widescreen/)"
fi

# Optional: pair with the user's `bing-image.service` so XDG pool keeps
# growing. We only intervene if the user already has `getBingImage.sh`
# on PATH and is currently being broken by a dead wpad.lan proxy.
BING_SCRIPT="$HOME/bin/getBingImage.sh"
if [[ -x "$BING_SCRIPT" ]] \
   && grep -q 'wpad\.lan' "$BING_SCRIPT" 2>/dev/null; then
  BING_DIR="$HOME/.config/systemd/user/bing-image.service.d"
  mkdir -p "$BING_DIR"
  if [[ ! -f "$BING_DIR/override.conf" ]]; then
    # Backup the user script for the edit we make next.
    cp -n "$BING_SCRIPT" "${BING_SCRIPT}.bak-$(date +%Y%m%d)" 2>/dev/null || true
    # Two-step fix:
    #  1. The script defaults PROXY="" (a one-line sed; commented
    #     to let user opt out).
    #  2. The wrapper below adds PROXY_OVERRIDE back when wpad is
    #     alive, so the script behaves correctly under both.
    sed -i 's|^PROXY="-x http://wpad\.lan:8888"|PROXY="${PROXY_OVERRIDE:-}"  # omarchy-on-debian: default off, wpad-down fall-back|' \
      "$BING_SCRIPT"
    cat > "$HOME/bin/bing-image-wrapper.sh" <<'WRAP'
#!/bin/bash
# Wrapper around ~/bin/getBingImage.sh — exports PROXY_OVERRIDE only
# when wpad.lan:8888 is actually reachable. See steps/73-wallpaper-rotate.sh
# for the rationale (the user file was hard-coding a dead proxy).
set -u
USER_SCRIPT="$HOME/bin/getBingImage.sh"
[[ -x "$USER_SCRIPT" ]] || { echo "[bing-wrapper] FAILED: $USER_SCRIPT" >&2; exit 127; }

probe=$(curl --max-time 2 --silent --output /dev/null \
              --proxy "http://wpad.lan:8888" \
              -w '%{http_code}' \
              "http://www.bing.com/HPImageArchive.aspx?format=js" 2>/dev/null \
         ; echo " CURL_RC=$?")

case "$probe" in
  *CURL_RC=0*|*CURL_RC=22*)
    echo "[bing-wrapper] wpad alive → export PROXY_OVERRIDE"
    export PROXY_OVERRIDE="-x http://wpad.lan:8888" ;;
  *)
    echo "[bing-wrapper] wpad dead ($probe) → PROXY_OVERRIDE off"
    export PROXY_OVERRIDE="" ;;
esac
exec "$USER_SCRIPT" "$@"
WRAP
    chmod +x "$HOME/bin/bing-image-wrapper.sh"

    cat > "$BING_DIR/override.conf" <<'UNIT'
# Drop-in: route `bing-image.service` through the wrapper so it
# survives the day wpad.lan:8888 stops responding.
[Service]
ExecStart=
ExecStart=%h/bin/bing-image-wrapper.sh
UNIT
    systemctl --user daemon-reload
    log "  wired bing-image.service → bing-image-wrapper.sh (proxy-aware)"
  fi
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
