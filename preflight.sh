#!/usr/bin/env bash
# preflight.sh — show what ./install.sh is about to do, WITHOUT changing anything.
#
#   ./preflight.sh            # full preview
#   ./preflight.sh --summary  # one-line verdict + the sudo/user split only
#   ./preflight.sh --quiet    # suppress the "what this means" prose
#
# Output is organised in three groups:
#   A. Environment checks        (read-only probes; nothing to authorise)
#   B. System-level changes      (will prompt for sudo/root; /etc + apt)
#   C. User-level writes         (no sudo; ~/.config ~/.local ~/.cargo ~/bin …)
#
# Every line is tagged with the install step that performs it, so you can
# cross-reference `./install.sh --only N` if you want to run pieces by hand.
set -uo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib/common.sh
. ./lib/common.sh

SUMMARY=0
QUIET=0
for a in "$@"; do
  case "$a" in
    --summary) SUMMARY=1 ;;
    --quiet)   QUIET=1 ;;
    *) echo "unknown option: $a" >&2; exit 1 ;;
  esac
done

# --------------------------------------------------------------------------
# A. Environment probes — read-only. Detects new-install vs upgrade and which
#    sudo'd package installs the steps will *actually* skip.
# --------------------------------------------------------------------------
apt_has() { dpkg -s "$1" >/dev/null 2>&1; }          # true if installed
pkg_cmd() { command -v "$1" >/dev/null 2>&1; }

is_debian=0; is_hypr=0; has_git=0; has_cargo=0
CODENAME="$(. /etc/os-release 2>/dev/null && echo "${VERSION_CODENAME:-trixie}")"
command -v apt-get >/dev/null 2>&1 && is_debian=1
[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] && is_hypr=1
pkg_cmd git   && has_git=1
pkg_cmd cargo && has_cargo=1

log "A. Environment checks (read-only)"
info "apt-based system ............ $([ "$is_debian" = 1 ] && echo yes || echo "NO — needs Debian/Ubuntu")"
info "running inside Hyprland .... $([ "$is_hypr" = 1 ] && echo yes || echo "no (binds apply at next login)")"
info "git ......................... $([ "$has_git" = 1 ] && echo present || echo "MISSING — step 20 needs it")"
info "cargo/rustup ................ $([ "$has_cargo" = 1 ] && echo "present ($(command -v cargo))" || echo "MISSING — step 73 needs it")"
if [ -d "$OMARCHY_HOME/shell" ]; then
  info "Omarchy already deployed .... yes (running this again = upgrade/re-fix; backups kept)"
else
  info "Omarchy already deployed .... no (fresh install)"
fi
[ -f "$HOME/.config/hypr/hyprland.conf" ] && info "Hyprland config present ...... yes (~/.config/hypr/hyprland.conf will be appended)"
echo

# --------------------------------------------------------------------------
# The sudo'd package-install lines are conditional: preflight says whether each
# step will actually prompt for sudo, based on what's already on the system.
# --------------------------------------------------------------------------
# Core packages step 10 installs (quickshell/hyprland come from backports).
CORE=(quickshell hyprland xdg-desktop-portal-hyprland jq bc curl wget unzip rsync
      imagemagick inotify-tools libxkbcommon-tools libnotify-bin polkitd pkexec
      wireplumber network-manager bluez bluez-utils power-profiles-daemon
      grim slurp wl-clipboard pipewire pipewire-pulse fonts-firacode fastfetch
      xdg-terminal-exec kitty)
OPT=(brightnessctl pamixer wtype hyprpicker hyprsunset gum cliphist swayidle swaylock)
QALC=; FZF=; APTUTILS=; PAM=1
apt_has qalc       || QALC="qalc"
pkg_cmd fzf        || FZF="fzf"
pkg_cmd apt-cache  || APTUTILS="apt-utils"
[ -f /etc/pam.d/omarchy-lock-password ] || PAM=0   # step 72 will create it

# --------------------------------------------------------------------------
# B. System-level changes (will ask for sudo/root).
# --------------------------------------------------------------------------
log "B. System-level changes — these will prompt for your password"
sudonote() { info "  $1"; }

sudonote "step 10  apt-get update + install core system packages:"
sudonote "         ${CORE[*]}"
missing_core=()
for p in "${CORE[@]}"; do apt_has "$p" || missing_core+=("$p"); done
if [ ${#missing_core[@]} -gt 0 ]; then
  sudonote "         → will actually install now: ${missing_core[*]}"
else
  sudonote "         → (all already present — no install prompt)"
fi
sudonote "         optional feature packages (skipped if unavailable): ${OPT[*]}"
sudonote "step 10  enable ${CODENAME:-trixie}-backports → writes /etc/apt/sources.list.d/ + /etc/apt/preferences.d/  (first run only)"
[ -n "${QALC:-}" ]         && sudonote "step 66  apt-get install $QALC (calculator)"
[ -n "${FZF:-}" ]          && sudonote "step 68  apt-get install $FZF (menu → Install/Remove picker)"
[ -n "${APTUTILS:-}" ]     && sudonote "step 68  apt-get install $APTUTILS (apt-cache for the picker)"
[ -f /etc/fastfetch/config.jsonc ] || sudonote "step 65  write /etc/fastfetch/config.jsonc (About screen layout)"
if [ "$PAM" = 0 ]; then
  sudonote "step 72  write /etc/pam.d/omarchy-lock-password (+ optional omarchy-lock-fingerprint)"
else
  sudonote "step 72  /etc/pam.d/omarchy-lock-password already present — no prompt"
fi
apt_has libpam-modules || sudonote "step 72  apt-get install libpam-modules (pam_unix for lock auth)"
sudonote "step 74  replace /etc/pam.d/hyprlock (drops pam_ecryptfs.so unwrap; original saved as hyprlock.bak-omarchy-on-debian)"
echo

# --------------------------------------------------------------------------
# C. User-level writes — no sudo. Files land under ~/.config ~/.local ~/.cargo
#    ~/bin ~/Pictures and the XDG state/autostart dirs.
# --------------------------------------------------------------------------
log "C. User-level writes — no password needed (your \$HOME only)"
uinote() { info "  $1"; }

uinote "step 20  clone Omarchy into ~/.cache/omarchy-on-debian/"
uinote "step 30  deploy shell/ + bin/ + config/ → ~/.local/share/omarchy/"
uinote "step 30  install launchers → ~/.local/bin/  (omarchy-port, omarchy-menu-toggle, uwsm-app shim)"
uinote "step 30  append a guarded PATH block to ~/.profile  (login-shell PATH for omarchy-*)"
uinote "step 40  apply compatibility patches inside ~/.local/share/omarchy/"
uinote "step 50  fonts → ~/.local/share/fonts/  + fontconfig override → ~/.config/fontconfig/"
uinote "step 60  append env/autostart/binds block to ~/.config/hypr/hyprland.conf"
uinote "step 65  ~/.config/hyprland-xdg-terminals.list + ~/.config/omarchy/branding/about.txt"
uinote "step 66  script → ~/.local/share/omarchy/bin/omacalc"
uinote "step 67  patch ~/.local/share/omarchy/bin/omarchy-hyprland-monitor-scaling"
uinote "step 68  replace pkg-add/remove/install wrappers in ~/.local/share/omarchy/bin/"
uinote "step 69  ~/.local/bin/omarchy-show-desktop + extra bind in ~/.config/hypr/hyprland.conf"
uinote "step 70  pin top bar → overlay layer (patch inside ~/.local/share/omarchy/)"
uinote "step 73  cargo install wpaperd + wpaperctl → ~/.cargo/bin/, symlinked to ~/.local/bin/"
uinote "step 73  ~/.config/autostart/wpaperd-autostart.desktop + ~/.config/wpaperd/wallpaper.toml"
uinote "step 74  ~/bin/wpaperd-ws-switch.py + ~/.config/autostart/wpaperd-ws-switch-autostart.desktop"
uinote "step 74  wallpapers → ~/Pictures/wallpapers/ (opt-in ws1/ ws2/ … sub-dirs) ; state → ~/.local/state/"
uinote "step 74  systemctl --user mask xdg-desktop-portal-hyprland.service  (user-level, no sudo)"
uinote "         (backups of any overwritten file → ~/.local/share/omarchy/.omarchy-on-debian/backups/)"
echo

# --------------------------------------------------------------------------
# Verdict
# --------------------------------------------------------------------------
log "What this means for you"
if [ "$SUMMARY" = 1 ]; then
  echo "→ sudo/root will be asked for: apt packages (steps 10/66/68/72) and /etc writes (65/72/74)."
  echo "→ Everything else is written under your \$HOME with no password."
  echo "→ Missing pre-reqs that steps expect but never install: cargo/rustup (needed by step 73)."
  exit 0
fi
info "• Run this every time before ./install.sh to review exactly what it will touch."
info "• Want zero surprises?  ./install.sh --dry-run  prints every command; nothing runs."
info "• Run one piece at a time?  ./install.sh --only N   (N = the step tag above)."
info "• cargo/rustup is a real pre-req only step 73 (wallpaper rotation) needs — if you"
info "  skip wallpaper you can set it aside, otherwise install rustup first (non-root)."
[ "$QUIET" = 1 ] || cat <<'EOF'

  Summary:  system packages → sudo   ·   ~/.config ~/.local ~/.cargo ~/bin → user
  Nothing has been changed by this script.
EOF
