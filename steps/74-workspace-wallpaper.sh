#!/usr/bin/env bash
# 74 — per-workspace wallpaper (wpaperd + generic switcher) + crash-bomb defusal.
# ------------------------------------------------------------------
# What this step does
#   * Picks **wpaperd** as the wallpaper daemon (installed in step 73)
#     and a small in-house Python listener, `~/bin/wpaperd-ws-switch.py`,
#     as the per-workspace engine. Hides **hyprpaper** fully (cleanup below).
#   * The wallpaper source is `~/Pictures/wallpapers/` (step 73 creates it
#     and points wpaperd at it). Per-workspace images are OPT-IN: create
#     `~/Pictures/wallpapers/ws1/ ws2/ …` sub-directories and fill each to
#     get a distinct image per workspace. Without them every workspace
#     shares the flat pool. The installer fetches nothing.
#   * Persists each workspace's "last-shown image" in
#     `~/.local/state/wpaperd-ws-state.json` so switching back to a
#     workspace shows exactly the image you last saw (no random re-pick,
#     no jarring swap). A background thread then picks a *different*
#     image every 5 minutes for whichever workspace is currently active.
#   * The active output is auto-detected at runtime (`hyprctl monitors -j`)
#     — nothing in the listener is hard-coded to a monitor name, so it
#     works on any single-screen laptop or multi-monitor setup.
#   * **Defuses two compositor time-bombs that were crashing the
#     compositor on every screen lock**:
#       1. `xdg-desktop-portal-hyprland.service` — masked. It SIGSEGVs
#          in `libwayland-client.so.0+0xbc8e` (wl_proxy_marshal_flags)
#          every time hyprlock reaches for a screenshot; the resulting
#          session tear-down then takes Hyprland with it.
#       2. `/etc/pam.d/hyprlock` — replaced. The Debian package's
#          drop-in inherits `pam_ecryptfs.so unwrap` from
#          `/etc/pam.d/common-auth`, which calls `seteuid()` against a
#          non-ecryptfs user and returns an error that hyprlock interprets
#          as a hard failure. The replacement contains only
#          `auth required pam_unix.so` so the wall flips back, the
#          password box appears, and the compositor survives.
#   * Updates `~/.config/hypr/hyprland.conf`:
#       - adds `exec-once = wpaperd` so the daemon is always alive,
#         even if the XDG-autostart service hasn't run yet;
#       - rebinds `Super+Ctrl+L` to `loginctl lock-session` instead of
#         `omarchy-system-lock` (the Quickshell path needs an extra PAM
#         service — see step 72 — and is the path most likely to fall
#         back on the same Portal/PAM chain that was crashing the
#         compositor).
#   * **Cleans up the Arch-prebuilt hyprpaper footprint** that an earlier
#     step-74 edition used to install:
#       - `~/.local/bin/hyprpaper`
#       - `~/.local/lib/libhyprlang.so.*` `libhyprutils.so.*`
#         `libhyprwire.so.*` `libhyprtoolkit.so.*`
#       - `~/.local/lib/libstdc++.so.6.0.36` (Arch GCC 16 libstdc++)
#       - `~/.local/lib/libm-243-shim.so` (14 KB GLIBC 2.43 math shim)
#       - `~/.config/autostart/hyprpaper-autostart.desktop` and
#         `hyprpaper-ws-switch-autostart.desktop`
#       - `~/.config/hypr/hyprpaper.conf` (it is the *only* symptom of
#         the old daemon; wpaperd and hyprpaper cannot both own the
#         background layer, so we drop hyprpaper's slot)
#
# Why not hyprpaper?
#   * Both `hyprpaper 0.8.4-1~bpo13+1` (Debian trixie-backports) **and**
#     `hyprpaper 0.8.4-8` (Arch extra) fail to connect to the live
#     Hyprland instance on this stack (Wayland fd-table never opens a
#     socket, IPC replies but rendering pipeline stays dead). That is
#     independent of the use-after-free covered in step 74's previous
#     edition. wpaperd is unaffected by the wlroots ABI drift and
#     survives Hyprland cleanly.
# ------------------------------------------------------------------
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"

log "74 — per-workspace wallpaper (generic switcher) + crash-bomb defusal"

WPAPERD_BIN="$HOME/.local/bin/wpaperd"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LISTENER_SRC="$REPO_ROOT/bin/wpaperd-ws-switch.py"
LISTENER_DST="$HOME/bin/wpaperd-ws-switch.py"
AUTOSTART_DIR="$HOME/.config/autostart"
WALL_DIR="$HOME/Pictures/wallpapers"
STATE_FILE="$HOME/.local/state/wpaperd-ws-state.json"
WPAPERD_CFG="$HOME/.config/wpaperd/wallpaper.toml"
HYPR_CONF_DIR="$HOME/.config/hypr"
HYPR_CONF="$HYPR_CONF_DIR/hyprland.conf"


# ---------------------------------------------------------------------------
# 0. Sanity — step 73 must have installed wpaperd first.
# ---------------------------------------------------------------------------
if [[ ! -x "$WPAPERD_BIN" && ! -x "$HOME/.cargo/bin/wpaperd" ]]; then
  die "wpaperd not installed. Run ./install.sh --only 73 first."
fi
ok "wpaperd binary present"


# ---------------------------------------------------------------------------
# 1. Cleanup — every artifact of the *previous* step 74 (hyprpaper +
#    Arch prebuilt + GLIBC 2.43 shim). Idempotent: missing files are
#    skipped without error.
# ---------------------------------------------------------------------------
log "  1. removing hyprpaper + Arch-private stash (idempotent)"
remove_if() {
  local what="$1" path="$2"
  if [[ -e "$path" ]]; then
    rm -f -- "$path" && info "    removed $what → $path"
  fi
}

remove_if "hyprpaper binary"          "$HOME/.local/bin/hyprpaper"
for f in \
    "$HOME/.local/lib/libhyprlang.so" \
    "$HOME/.local/lib/libhyprlang.so.2" \
    "$HOME/.local/lib/libhyprlang.so.0.6.8" \
    "$HOME/.local/lib/libhyprutils.so" \
    "$HOME/.local/lib/libhyprutils.so.13" \
    "$HOME/.local/lib/libhyprutils.so.0.14.1" \
    "$HOME/.local/lib/libhyprwire.so" \
    "$HOME/.local/lib/libhyprwire.so.3" \
    "$HOME/.local/lib/libhyprwire.so.0.3.1" \
    "$HOME/.local/lib/libhyprtoolkit.so" \
    "$HOME/.local/lib/libhyprtoolkit.so.5" \
    "$HOME/.local/lib/libhyprtoolkit.so.0.5.4" \
    "$HOME/.local/lib/libstdc++.so" \
    "$HOME/.local/lib/libstdc++.so.6" \
    "$HOME/.local/lib/libstdc++.so.6.0.36" \
    "$HOME/.local/lib/libm-243-shim.so"; do
  remove_if "Arch lib"               "$f"
done

# Old ws-switch listener (every variant step 74 has ever shipped).
remove_if "old hyprpaper listener"   "$HOME/bin/hyprpaper-ws-switch.py"
remove_if "old ws-switch listener"   "$HOME/bin/wpaperd-ws-switch.py.disabled"

# Old XDG autostart entries.
remove_if "hyprpaper daemon autostart"  "$AUTOSTART_DIR/hyprpaper-autostart.desktop"
remove_if "hyprpaper ws autostart"      "$AUTOSTART_DIR/hyprpaper-ws-switch-autostart.desktop"

# Old hyprpaper config file.
remove_if "hyprpaper.conf" "$HYPR_CONF_DIR/hyprpaper.conf"

# Old systemd user unit (if any).
for f in "$HOME/.local/lib/hyprpaper" \
         "$HOME/.local/share/hyprpaper"; do
  [[ -d "$f" ]] && rm -rf -- "$f" && info "    removed dir $f"
done

if [[ -f "$HOME/.config/systemd/user/hyprpaper.service" ]]; then
  systemctl --user disable --now hyprpaper.service 2>/dev/null || true
  rm -f -- "$HOME/.config/systemd/user/hyprpaper.service"
  systemctl --user daemon-reload
  info "    disabled and removed hyprpaper.service"
fi


# ---------------------------------------------------------------------------
# 2. Wallpaper source directory.
#    Step 73 already creates ~/Pictures/wallpapers/ and points wpaperd at
#    it. Nothing to fetch. Per-workspace pools are OPT-IN: a user who
#    wants a distinct image per workspace simply makes `ws1/ ws2/ …`
#    sub-directories and drops images in each — the listener prefers
#    `wsN/` when present and otherwise falls back to the flat directory.
#    We only make sure the top-level dir exists so the listener has a
#    valid fallback even on a re-run that skipped step 73.
# ---------------------------------------------------------------------------
log "  2. ensuring wallpaper source dir exists"
mkdir -p "$WALL_DIR"
ok "wallpaper source: $WALL_DIR (add ws1/ ws2/ … sub-dirs to opt into per-workspace images)"


# ---------------------------------------------------------------------------
# 3. Install the per-workspace listener. It is a self-contained Python
#    file in this repo; install_file() makes a one-shot timestamped
#    backup if it diverges.
# ---------------------------------------------------------------------------
log "  3. installing the per-workspace listener"
if [[ ! -f "$LISTENER_SRC" ]]; then
  die "missing $LISTENER_SRC — pull the repo first"
fi
install_file "$LISTENER_SRC" "$LISTENER_DST" 0755
ok "wrote $LISTENER_DST"

mkdir -p "$(dirname "$STATE_FILE")"
if [[ ! -f "$STATE_FILE" ]]; then
  printf '{}\n' > "$STATE_FILE"
  ok "initialised empty state file at $STATE_FILE"
fi


# ---------------------------------------------------------------------------
# 4. wpaperd configuration — owned by step 73 (generic [default] + [any]
#    pointing at ~/Pictures/wallpapers). This step must NOT clobber it
#    with a monitor-specific file: the per-workspace switcher adds the
#    [<active monitor>] single-file block at runtime. We only sanity-check
#    that a config exists and warn if it looks like an old hard-coded one.
# ---------------------------------------------------------------------------
log "  4. checking wpaperd configuration"
if [[ ! -f "$WPAPERD_CFG" ]]; then
  warn "  $WPAPERD_CFG missing — run step 73 first to generate the generic config"
else
  # A stale config from an earlier omarchy-on-debian release may still
  # hard-code eDP-1/DP-4; pointing those back at the pool by hand is
  # fiddly, so we just tell the user to regenerate a clean generic file.
  if grep -qE '^\[(eDP-1|DP-4)\]' "$WPAPERD_CFG"; then
    warn "  $WPAPERD_CFG still has old monitor-specific blocks ([eDP-1]/[DP-4])."
    warn "  Re-run ./install.sh --only 73 to regenerate the generic config."
  else
    ok "  generic wpaperd config present"
  fi
fi


# ---------------------------------------------------------------------------
# 5. Defuse the two compositor time-bombs.
# ---------------------------------------------------------------------------
log "  5. masking xdg-desktop-portal-hyprland (compositor-crash bomber)"

if command -v systemctl >/dev/null; then
  if systemctl --user mask xdg-desktop-portal-hyprland.service 2>/dev/null; then
    systemctl --user stop xdg-desktop-portal-hyprland.service 2>/dev/null || true
    ok "  xdg-desktop-portal-hyprland.service masked"
  else
    warn "  could not mask xdg-desktop-portal-hyprland.service"
    warn "  run manually: systemctl --user mask xdg-desktop-portal-hyprland.service"
  fi
else
  warn "  systemctl(1) not available, skipping portal mask"
fi

log "  6. replacing /etc/pam.d/hyprlock (drops pam_ecryptfs.so unwrap)"
if [[ -w /etc/pam.d/hyprlock || ${EUID:-$(id -u)} -eq 0 ]]; then
  if [[ -f /etc/pam.d/hyprlock.bak-omarchy-on-debian ]]; then
    info "    /etc/pam.d/hyprlock already replaced (marker preserved)"
  else
    cp /etc/pam.d/hyprlock /etc/pam.d/hyprlock.bak-omarchy-on-debian 2>/dev/null || true
    cat > /etc/pam.d/hyprlock <<'PAM'
# /etc/pam.d/hyprlock — omarchy-on-debian override.
#
# The Debian package's drop-in `/etc/pam.d/hyprlock` is `include
# common-auth`, which forces `pam_ecryptfs.so unwrap` and triggers a
# seteuid error whenever the user is *not* on a `~/.ecryptfs`
# filesystem (the common Debian-trixie case). That error then kills
# the Hyprland compositor from underneath hyprlock.
#
# Replaced with a minimal configuration that authenticates against
# /etc/shadow via pam_unix. Lives next to the original at
# /etc/pam.d/hyprlock.bak-omarchy-on-debian if you need to roll it
# back.
auth     required    pam_unix.so nullok
account  required    pam_unix.so
PAM
    ok "  replaced /etc/pam.d/hyprlock (pam_ecryptfs.so unwrap removed)"
  fi
else
  warn "  not root and /etc/pam.d/hyprlock is not writable"
  warn "  run the block under §6 yourself with sudo (see TROUBLESHOOTING §14)"
fi


# ---------------------------------------------------------------------------
# 6. hyprland.conf — drop in our exec-once + the right bind for
#    Super+Ctrl+L (lockctl lock-session, the same path the 5-min idle
#    trigger already takes). The old `exec-once = hyprpaper` line stays
#    in place but is left commented: keeping it means re-running step
#    73 after a future reinstall will see the right marker.
# ---------------------------------------------------------------------------
log "  7. wiring hyprland.conf"
if [[ -f "$HYPR_CONF" ]]; then
  # exec-once = wpaperd (and the ws-switch listener)
  if grep -qE '^#? *exec-once *= *wpaperd$' "$HYPR_CONF"; then
    sed -i 's|^# *exec-once *= *wpaperd$|exec-once = wpaperd|' "$HYPR_CONF"
  else
    printf '\nexec-once = wpaperd\n' >> "$HYPR_CONF"
  fi

  if grep -qE '^#? *exec-once *= *wpaperd-ws-switch\.py$' "$HYPR_CONF"; then
    sed -i 's|^# *exec-once *= *wpaperd-ws-switch\.py$|exec-once = wpaperd-ws-switch.py|' "$HYPR_CONF"
  else
    printf 'exec-once = wpaperd-ws-switch.py\n' >> "$HYPR_CONF"
  fi

  # Re-bind Super+Ctrl+L (was pointing at omarchy-system-lock, which
  # needs the Quickshell lock plugin + a working /etc/pam.d/
  # omarchy-lock-password to authenticate). Take the same lockctl
  # path that the 5-min idle takes; both now hit hyprlock without
  # Portal or ecryptfs involvement.
  if grep -qE '^#? *bind *= *\$mainMod CTRL, *L,' "$HYPR_CONF"; then
    sed -i 's|^bind = \$mainMod CTRL, *L, *exec, *omarchy-system-lock.*|bind = $mainMod CTRL, L, exec, loginctl lock-session                  # Lock computer|' "$HYPR_CONF"
  fi

  # Comment out the now-dead `exec-once = hyprpaper` line if it exists.
  if grep -qE '^exec-once *= *hyprpaper$' "$HYPR_CONF"; then
    sed -i 's|^exec-once *= *hyprpaper$|# exec-once = hyprpaper omarchy: wpaperd takes over wallpaper slot|' "$HYPR_CONF"
  fi
  ok "  hyprland.conf updated"
else
  warn "  ~/.config/hypr/hyprland.conf missing — skipped"
fi


# ---------------------------------------------------------------------------
# 7. XDG autostart — keep step 73's wpaperd entry; add a sibling entry
#    for the listener. Both have to survive a relaunch even when no one
#    has logged into a Hyprland session yet.
# ---------------------------------------------------------------------------
log "  8. installing XDG autostart entries"
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/wpaperd-ws-switch-autostart.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=wpaperd-ws-switch
GenericName=Hyprland → wpaperd per-workspace bridge
Comment=Listens on \$XDG_RUNTIME_DIR/hypr/.../socket2.sock for workspacev2 events
        and rewrites the active monitor's path in wallpaper.toml (monitor
        auto-detected). Maintains per-workspace state at
        ~/.local/state/wpaperd-ws-state.json; background timer rotates the
        active workspace's image every 5 minutes.
Exec=python3 $LISTENER_DST
Terminal=false
NoDisplay=true
Categories=Utility;
DESKTOP
ok "wrote $AUTOSTART_DIR/wpaperd-ws-switch-autostart.desktop"


# ---------------------------------------------------------------------------
# 8. Kickoff — start wpaperd + listener so they are alive without
#    requiring a Hyprland restart. Safe to re-run.
# ---------------------------------------------------------------------------
log "  9. kicking off the live daemons"
if pgrep -x wpaperd >/dev/null; then
  ok "  wpaperd already running"
else
  setsid "$WPAPERD_BIN" >/tmp/wpaperd-step74.log 2>&1 < /dev/null &
  disown || true
  sleep 1
fi
if pgrep -af "$LISTENER_DST" >/dev/null; then
  ok "  wpaperd-ws-switch already running"
else
  setsid python3 "$LISTENER_DST" >/tmp/wpaperd-ws-switch-step74.log 2>&1 < /dev/null &
  disown || true
  sleep 1
fi


ok "step 74 complete — wallpaper & lockchain ready"

cat <<EOF

Result:
  • wallpaper daemon: wpaperd  ($(command -v wpaperd))
  • per-workspace:    bin/wpaperd-ws-switch.py (active output auto-detected + 5-min rotation)
  • source:           $WALL_DIR  (opt into per-workspace with ws1/ ws2/ … sub-dirs)
  • state:            $STATE_FILE
  • lock chain:       /etc/pam.d/hyprlock (pam_unix only)
                      xdg-desktop-portal-hyprland.service (masked)
                      Super+Ctrl+L → loginctl lock-session (no Portal)

Verify:
  wpaperctl get-wallpaper <your-monitor>   # e.g. run `hyprctl monitors -j` for names
  systemctl --user status xdg-desktop-portal-hyprland.service   # should be masked
  cat /etc/pam.d/hyprlock                                       # should reference pam_unix
EOF
