#!/usr/bin/env bash
# 10 — packages. Quickshell and Hyprland 0.55 need trixie-backports on Debian 13.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

command -v apt-get >/dev/null || die "this step expects apt (Debian/Ubuntu)"

need_sudo() { command -v sudo >/dev/null && echo sudo || echo; }
SUDO="$(need_sudo)"
[ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ] && die "need root or sudo to install packages"

CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-trixie}")"

run $SUDO apt-get update -qq

# --- backports: quickshell / hyprland / xdg-desktop-portal-hyprland
# LC_ALL=C: apt-cache output is localized, and a zh_CN locale turns
# "Candidate:" into something else, which would re-add the repo every run.
if [ "$(LC_ALL=C apt-cache policy quickshell 2>/dev/null | awk '/Candidate:/{print $2}')" = "(none)" ]; then
  info "enabling $CODENAME-backports"
  printf 'deb http://deb.debian.org/debian %s-backports main contrib non-free-firmware\n' "$CODENAME" |
    run $SUDO tee "/etc/apt/sources.list.d/$CODENAME-backports.list" >/dev/null
  printf 'Package: *\nPin: release n=%s-backports\nPin-Priority: 100\n' "$CODENAME" |
    run $SUDO tee "/etc/apt/preferences.d/99-$CODENAME-backports" >/dev/null
  run $SUDO apt-get update -qq
fi

# --- core: what the shell and its QML plugins actually exec
PACKAGES=(
  quickshell hyprland xdg-desktop-portal-hyprland
  jq bc curl wget unzip rsync imagemagick
  inotify-tools                 # QML hot-reload (panel/plugin file watchers)
  libxkbcommon-tools            # provides xkbcli
  libnotify-bin                 # notify-send
  polkitd pkexec                # GUI sudo for menu actions (timezone, etc)
  wireplumber                   # wpctl: audio
  network-manager               # nmcli: wifi
  bluez bluez-utils             # bluetoothctl
  power-profiles-daemon         # powerprofilesctl
  grim slurp wl-clipboard       # screenshots / clipboard
  pipewire pipewire-pulse
  fonts-firacode
)

# --- optional, feature-gated: skip anything the repo does not carry
OPTIONAL=(
  brightnessctl                 # OSD brightness keys
  pamixer                       # OSD volume
  wtype                         # typing into focused window
  hyprpicker                    # colour picker menu
  hyprsunset                    # night light
  gum                           # TUI pickers used by some omarchy-* scripts
  cliphist                      # clipboard history
  swayidle swaylock             # idle / lock
)

MISSING=()
for p in "${PACKAGES[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
[ ${#MISSING[@]} -gt 0 ] && run $SUDO apt-get install -y --no-install-recommends "${MISSING[@]}"
[ ${#MISSING[@]} -eq 0 ] && ok "core packages present" || ok "core packages installed"

OPT_MISSING=()
for p in "${OPTIONAL[@]}"; do
  dpkg -s "$p" >/dev/null 2>&1 || OPT_MISSING+=("$p")
done
if [ ${#OPT_MISSING[@]} -gt 0 ]; then
  info "optional (features stay hidden without them): ${OPT_MISSING[*]}"
  run $SUDO apt-get install -y --no-install-recommends "${OPT_MISSING[@]}" ||
    warn "some optional packages unavailable — install them manually later"
else
  ok "optional packages present"
fi

# --- Nerd Font glyphs: Debian ships no nerd fonts, and the shell's weather,
#     update and system icons live in the U+E3xx PUA. Download if absent.
if ! has nerd fc-list; then
  warn "no Nerd Font found — downloading FiraCode Nerd Font"
  run mkdir -p "$HOME/.local/share/fonts"
  run bash -c "cd '$HOME/.local/share/fonts' && \
    curl -fsSLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/FiraCode.tar.xz && \
    tar xf FiraCode.tar.xz && rm -f FiraCode.tar.xz"
  run fc-cache -f >/dev/null
else
  ok "Nerd Font present"
fi
