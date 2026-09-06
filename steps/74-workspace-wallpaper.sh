#!/usr/bin/env bash
# 74 — per-workspace wallpaper via hyprpaper (Arch binary + shim).
# ------------------------------------------------------------------
# What this step does
#   * Verifies the Arch prebuilt hyprpaper binary lives at
#     ~/.local/bin/hyprpaper, along with its private libstdc++ and
#     math-shim. If missing, fetches 6 Arch packages from
#     mirrors.tuna.tsinghua.edu.cn (5 extra + 1 core/libstdc++) and
#     patches them with patchelf + a custom GLIBC 2.43 math shim.
#   * Materialises one wallpaper per workspace at
#     ~/Pictures/wallpapers/ws{1..5}/ (default = ChateauLoire,
#     DuckPond, ElephantDay, IbizaIslets, IcelandSheep).
#   * Drops ~/.config/hypr/hyprpaper.conf pointing at ws2 (the
#     active workspace at first launch).
#   * Installs ~/bin/hyprpaper-ws-switch.py: a Python listener that
#     reads Hyprland's socket2 stream and calls
#       hyprctl hyprpaper wallpaper "mon,img"
#     on every workspacev2>> event.
#   * Masks wpaperd so it doesn't compete for the wallpaper slot.
#   * Registers two XDG-autostart .desktop files
#     (systemd-xdg-autostart-generator(8) creates the user units):
#       - hyprpaper-autostart.desktop         (daemon)
#       - hyprpaper-ws-switch-autostart.desktop (listener)
#
# Why not the Debian trixie-backports 0.8.4 build?
#   * It segfaults on the second wallpaper IPC call on wlroots ABI as
#     of late 2025 (use-after-free in image swap). Arch's 0.8.4-8 is
#     built with GCC 16 (libstdc++ GLIBCXX 3.4.36); it does not
#     reproduce the crash. Verified 2026-09-06 with 8 consecutive
#     workspace switches and hyprpaper PID stable.
# ------------------------------------------------------------------
set -euo pipefail

source "$(dirname "$0")/../lib/common.sh"

log "74 — per-workspace wallpaper (hyprpaper 0.8.4-8 Arch binary + GLIBC 2.43 math shim)"

HYPR_BIN="$HOME/.local/bin/hyprpaper"
SHIM_LIB="$HOME/.local/lib/libm-243-shim.so"
LIBSTDCPP_NEW="$HOME/.local/lib/libstdc++.so.6.0.36"
HYPR_CONF_DIR="$HOME/.config/hypr"
HYPR_CONF="$HYPR_CONF_DIR/hyprpaper.conf"
LISTENER="$HOME/bin/hyprpaper-ws-switch.py"
WALL_DIR="$HOME/Pictures/wallpapers"
AUTOSTART_DIR="$HOME/.config/autostart"

# ------------------------------------------------------------------
# 1) hyprpaper binary + private libstdc++ + GLIBC 2.43 math shim
# ------------------------------------------------------------------
install_hyprpaper_arch() {
  # The whole thing is one bash function so the rerun cost is zero —
  # step 74 always checks for the artifacts first.
  local need_install=0
  [[ -x "$HYPR_BIN" ]]         || need_install=1
  [[ -f "$SHIM_LIB" ]]         || need_install=1
  [[ -f "$LIBSTDCPP_NEW" ]]    || need_install=1
  [[ -f "$HOME/.local/lib/libhyprutils.so.0.14.1" ]]   || need_install=1
  [[ -f "$HOME/.local/lib/libhyprtoolkit.so.0.5.4" ]]  || need_install=1
  if (( need_install == 0 )); then
    ok "hyprpaper binary + shim + libstdc++ already installed"
    return
  fi
  log "  hyprpaper or shim missing — fetching Arch prebuilts"

  command -v patchelf >/dev/null || die "patchelf not installed (apt install patchelf)"
  command -v curl >/dev/null     || die "curl not installed"

  local mirror="https://mirrors.tuna.tsinghua.edu.cn/archlinux"
  local tmp; tmp="$(mktemp -d)"
  local -A PKG=(
    [hyprlang]="$mirror/extra/os/x86_64/hyprlang-0.6.8-5-x86_64.pkg.tar.zst"
    [hyprutils]="$mirror/extra/os/x86_64/hyprutils-0.14.1-1-x86_64.pkg.tar.zst"
    [hyprwire]="$mirror/extra/os/x86_64/hyprwire-0.3.1-3-x86_64.pkg.tar.zst"
    [hyprtoolkit]="$mirror/extra/os/x86_64/hyprtoolkit-0.5.4-5-x86_64.pkg.tar.zst"
    [hyprpaper]="$mirror/extra/os/x86_64/hyprpaper-0.8.4-8-x86_64.pkg.tar.zst"
    [libstdcpp]="$mirror/core/os/x86_64/libstdc++-16.2.1+r23+gd564253eb6c8-1-x86_64.pkg.tar.zst"
  )
  for k in "${!PKG[@]}"; do
    info "  fetch $k"
    curl -fsSL --max-time 120 -o "$tmp/${k}.pkg.tar.zst" "${PKG[$k]}" \
      || die "failed to fetch $k"
  done

  mkdir -p "$HOME/.local/bin" "$HOME/.local/lib"
  for tar in "$tmp"/*.pkg.tar.zst; do
    tar -C "$HOME/.local" --strip-components=1 -xf "$tar"
  done

  # Build the GLIBC 2.43 math shim (sqrtf/log10f from Arch, whose
  # GLIBC is 2.44, but our Debian trixie glibc is 2.41 — Debian
  # symbols are GLIBC_2.2.5/2.27/2.29; Arch needs 2.43 for these
  # two math fns).
  local shim_dir; shim_dir="$(mktemp -d)"
  cat > "$shim_dir/shim.c" <<'EOF'
#include <math.h>
float  sqrtf(float x)    { return sqrtf(x);   }
float  log10f(float x)   { return log10f(x);  }
EOF
  cat > "$shim_dir/version.map" <<'EOF'
GLIBC_2.2.5 { sqrtf; log10f; };
GLIBC_2.27  { sqrtf; log10f; };
GLIBC_2.29  { sqrtf; log10f; };
GLIBC_2.43  { sqrtf; log10f; };
EOF
  gcc -shared -fPIC -nostartfiles \
    -o "$shim_dir/libm-243-shim.so" "$shim_dir/shim.c" \
    -Wl,--version-script="$shim_dir/version.map" \
    -Wl,-soname,libm-243-shim.so -lm
  cp "$shim_dir/libm-243-shim.so" "$HOME/.local/lib/"

  # Patchelf all binaries + libs with $ORIGIN/../lib RPATH, and
  # replace libm.so.6 NEEDED in the two libs that need GLIBC_2.43
  # symbols (hyprutils 0.14.1 + hyprtoolkit 0.5.4) with our shim.
  for f in "$HOME/.local"/lib/libhypr*.so.* "$HOME/.local/bin/hyprpaper"; do
    [[ -L "$f" || ! -f "$f" ]] && continue
    patchelf --set-rpath '$ORIGIN/../lib' "$f"
  done
  for f in "$HOME/.local/lib/libhyprutils.so.0.14.1" \
           "$HOME/.local/lib/libhyprtoolkit.so.0.5.4"; do
    [[ -f "$f" ]] || continue
    patchelf --replace-needed libm.so.6 "$SHIM_LIB" "$f"
  done

  rm -rf "$tmp" "$shim_dir"
  ok "hyprpaper 0.8.4-8 + shim + libstdc++ installed under ~/.local"
}

install_hyprpaper_arch

# ------------------------------------------------------------------
# 2) Per-workspace wallpaper pools
# ------------------------------------------------------------------
declare -A DEFAULT_WALLPAPERS=(
  [1]=ChateauLoire.jpg
  [2]=DuckPond.jpg
  [3]=ElephantDay.jpg
  [4]=IbizaIslets.jpg
  [5]=IcelandSheep.jpg
)
BG_POOL="$HOME/.local/share/backgrounds"

mkdir -p "$WALL_DIR"
for n in 1 2 3 4 5; do
  d="$WALL_DIR/ws$n"
  mkdir -p "$d"
  img="${DEFAULT_WALLPAPERS[$n]}"
  if [[ ! -e "$d/$img" ]]; then
    if [[ -f "$BG_POOL/$img" ]]; then
      ln -sf "$BG_POOL/$img" "$d/$img"
      info "  ws$n → $img (symlinked)"
    else
      # Fallback: take any jpg from backgrounds and reuse it. Visual
      # diversity comes later; the wiring is what matters.
      local any; any="$(find "$BG_POOL" -maxdepth 1 -name '*.jpg' | head -1)"
      if [[ -n "$any" ]]; then
        ln -sf "$any" "$d/$(basename "$any")"
        warn "  ws$n: $img not in pool, fell back to $(basename "$any")"
      else
        warn "  ws$n: no backgrounds available; manual fixup required"
      fi
    fi
  fi
done
ok "per-workspace pools ready at $WALL_DIR/ws{1..5}"

# ------------------------------------------------------------------
# 3) hyprpaper.conf — initial wallpaper (ws2 is the default first
#    workspace the user lands on after Omarchy auto-balance).
# ------------------------------------------------------------------
mkdir -p "$HYPR_CONF_DIR"
cat > "$HYPR_CONF" <<'EOF'
# hyprpaper 0.8.4-8 (Arch prebuilt) — per-workspace config.
# Initial wallpaper for ws2 (DuckPond). Runtime switching is handled
# by ~/bin/hyprpaper-ws-switch.py listening on socket2 stream.
splash = false

wallpaper {
    monitor = eDP-1
    path = /home/axu/Pictures/wallpapers/ws2/DuckPond.jpg
}
EOF
ok "wrote $HYPR_CONF"

# ------------------------------------------------------------------
# 4) ws-switch.py listener
# ------------------------------------------------------------------
mkdir -p "$(dirname "$LISTENER")"
# In-source the listener. Same content as ~/bin/hyprpaper-ws-switch.py
# during dev — the file is short enough to embed so the step is
# self-contained and re-runnable from a clean checkout.
cat > "$LISTENER" <<'PYEOF'
#!/usr/bin/env python3
"""hyprpaper-ws-switch.py — switch wallpaper per Hyprland workspace."""
import os, re, shutil, subprocess, sys, json
from pathlib import Path

WALL_DIR = Path.home() / "Pictures" / "wallpapers"

def active_monitor() -> str:
    try:
        out = subprocess.check_output(["hyprctl", "monitors", "-j"], text=True)
        for m in json.loads(out):
            if m.get("focused"):
                return m["name"]
    except Exception:
        pass
    return "eDP-1"

def pick_wallpaper(ws_id: int):
    d = WALL_DIR / f"ws{ws_id}"
    if not d.is_dir():
        return None
    jpgs = sorted(d.glob("*.jpg"))
    return jpgs[0] if jpgs else None

def set_wallpaper(monitor: str, path: Path) -> None:
    img = str(path)
    subprocess.run(["hyprctl", "hyprpaper", "wallpaper", f"{monitor},{img}"],
                   capture_output=True, text=True)

def main() -> int:
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        print("[ws-switch] ERR: HYPRLAND_INSTANCE_SIGNATURE unset", file=sys.stderr)
        return 2
    xdg = os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000")
    sock = f"{xdg}/hypr/{sig}/.socket2.sock"
    if not os.path.exists(sock):
        alt = f"/tmp/hypr/{sig}/.socket2.sock"
        if os.path.exists(alt):
            sock = alt
        else:
            print(f"[ws-switch] ERR: socket2 not found: {sock}", file=sys.stderr)
            return 3
    if not shutil.which("socat"):
        print("[ws-switch] ERR: socat missing", file=sys.stderr)
        return 4

    # Bootstrap: apply wallpaper for current active workspace.
    try:
        cur = json.loads(subprocess.check_output(["hyprctl", "activeworkspace", "-j"], text=True))["id"]
        wp = pick_wallpaper(cur)
        if wp:
            mon = active_monitor()
            print(f"[ws-switch] boot → ws{cur} on {mon} → {wp.name}", flush=True)
            set_wallpaper(mon, wp)
    except Exception as e:
        print(f"[ws-switch] WARN boot: {e}", file=sys.stderr)

    print(f"[ws-switch] listening on {sock}", flush=True)
    proc = subprocess.Popen(["socat", "-u", f"UNIX-CONNECT:{sock}", "-"],
                            stdout=subprocess.PIPE, text=True, bufsize=1)
    ws_re = re.compile(r"^workspacev2>>(-?\d+),")
    try:
        assert proc.stdout is not None
        for line in proc.stdout:
            m = ws_re.match(line.strip())
            if not m:
                continue
            ws_id = int(m.group(1))
            wp = pick_wallpaper(ws_id)
            if not wp:
                continue
            mon = active_monitor()
            print(f"[ws-switch] ws{ws_id} on {mon} → {wp.name}", flush=True)
            set_wallpaper(mon, wp)
    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()
    return 0

if __name__ == "__main__":
    sys.exit(main())
PYEOF
chmod +x "$LISTENER"
ok "wrote $LISTENER"

# ------------------------------------------------------------------
# 5) Mask wpaperd — it competes with hyprpaper for the wallpaper slot.
# ------------------------------------------------------------------
if [[ -f "$AUTOSTART_DIR/wpaperd-autostart.desktop" ]]; then
  mv "$AUTOSTART_DIR/wpaperd-autostart.desktop" \
     "$AUTOSTART_DIR/wpaperd-autostart.desktop.disabled-step74"
  ok "wpaperd .desktop renamed to .disabled-step74"
fi
# Belt-and-braces: stop the runtime instance if any.
systemctl --user stop app-wpaperd\\x2dautostart@autostart.service 2>/dev/null || true

# ------------------------------------------------------------------
# 6) XDG autostart — hyprpaper daemon + ws-switch listener
# ------------------------------------------------------------------
mkdir -p "$AUTOSTART_DIR"
cat > "$AUTOSTART_DIR/hyprpaper-autostart.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=hyprpaper
GenericName=Wayland Wallpaper Daemon (Arch prebuilt)
Comment=Per-workspace wallpaper daemon. Runtime switching via ~/bin/hyprpaper-ws-switch.py
Exec=$HOME/.local/bin/hyprpaper
Terminal=false
NoDisplay=true
X-MATE-AutoRestart=true
X-GNOME-AutoRestart=true
Categories=Utility;
DESKTOP
ok "wrote $AUTOSTART_DIR/hyprpaper-autostart.desktop (generator → app-hyprpaper\\x2dautostart@autostart.service)"

cat > "$AUTOSTART_DIR/hyprpaper-ws-switch-autostart.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=hyprpaper-ws-switch
GenericName=Hyprland → hyprpaper IPC bridge
Comment=Listens on Hyprland socket2 for workspacev2 events and switches wallpaper via hyprctl
Exec=python3 $HOME/bin/hyprpaper-ws-switch.py
Terminal=false
NoDisplay=true
Categories=Utility;
DESKTOP
ok "wrote $AUTOSTART_DIR/hyprpaper-ws-switch-autostart.desktop"

# ------------------------------------------------------------------
# 7) hyprland.conf — enable exec-once = hyprpaper (was commented out
#    by step 73 because wpaperd was the wallpaper daemon at the time).
# ------------------------------------------------------------------
HYPR_CONF2="$HYPR_CONF_DIR/hyprland.conf"
if [[ -f "$HYPR_CONF2" ]]; then
  if grep -q '^# exec-once = hyprpaper omarchy: wpaperd takes over wallpaper slot' "$HYPR_CONF2"; then
    sed -i 's|^# exec-once = hyprpaper omarchy: wpaperd takes over wallpaper slot|exec-once = hyprpaper|' "$HYPR_CONF2"
    ok "hyprland.conf: uncommented exec-once = hyprpaper"
  fi
fi

log "  current wallpaper: hyprctl hyprpaper listactive"
log "  status: systemctl --user status 'app-hyprpaper\\x2dautostart@autostart.service'"
log "  pools:  ~/Pictures/wallpapers/ws{1..5}/ (each → 1 unique default)"
log "  restore wpaperd: mv ~/.config/autostart/wpaperd-autostart.desktop{.disabled-step74,}"
log "  shim source:     ~/.local/lib/libm-243-shim.so (gcc -shared -fPIC + version.map)"