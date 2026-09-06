#!/usr/bin/env bash
# 68 — apt-driven package management: replace the pacman-based picker
# scripts that Omarchy's menu invokes.
#
# The four scripts that drive the menu's "Install Package" and "Remove
# Package" entries are upstream hardcoded against pacman / yay:
#
#   omarchy-pkg-install   (TUI: browse all repo packages → install)
#   omarchy-pkg-remove    (TUI: browse manually-installed → remove)
#   omarchy-pkg-add       (idempotent installer; called by 90+ wrappers)
#   omarchy-pkg-drop      (idempotent remover;  called by 90+ wrappers)
#   omarchy-pkg-missing   (predicate: is a package missing?)
#
# Reimplement these on Debian against apt-get / apt-cache / apt-mark /
# dpkg-query without touching any of the 90+ omarchy-install-* /
# omarchy-remove-* app wrappers — they call pkg-add / pkg-drop, whose
# public interface is unchanged.
#
# apt-cache (the binary used to list available packages) ships in the
# apt-utils package, which Debian does not install by default. fzf is
# required for the TUI. We pre-flight both with a sudo-able apt-get.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

REPO="$(pwd)"
OMARCHY_PATH="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
OMARCHY_BIN="$OMARCHY_PATH/bin"

need_sudo() { command -v sudo >/dev/null && echo sudo || echo; }
SUDO="$(need_sudo)"

PORT_MARKER='# This is the omarchy-on-debian port:'
BACKUP_DIR="$OMARCHY_BIN/.bak-20260906-pacman"

# --- 1) apt-utils + fzf ---
if ! command -v apt-cache >/dev/null 2>&1; then
  info "apt-cache missing — apt-get install -y apt-utils"
  run $SUDO apt-get update -y
  run $SUDO apt-get install -y apt-utils
fi
if ! command -v fzf >/dev/null 2>&1; then
  info "fzf missing — apt-get install -y fzf"
  run $SUDO apt-get install -y fzf
fi

# --- 2) deploy the five apt-driven scripts ---
mkdir -p "$OMARCHY_BIN"
mkdir -p "$BACKUP_DIR"

deploy_one() {
  local name="$1"
  local src="$REPO/bin/$name"
  local dst="$OMARCHY_BIN/$name"

  [ -f "$src" ] || die "missing source: $src"

  # Already the apt version? Skip.
  if [ -f "$dst" ] && head -n5 "$dst" | grep -qF "$PORT_MARKER"; then
    ok "$name already deployed (apt version)"
    return 0
  fi

  # Back up the upstream (pacman) version if it's still there, so the user
  # can roll back manually if they want the upstream behavior.
  if [ -f "$dst" ] && ! [ -f "$BACKUP_DIR/$name" ]; then
    run cp -p "$dst" "$BACKUP_DIR/$name"
    ok "backed up upstream $name to $BACKUP_DIR/"
  fi

  run cp "$src" "$dst"
  run chmod +x "$dst"
  ok "deployed $name (apt version)"
}

for n in omarchy-pkg-install omarchy-pkg-remove omarchy-pkg-add omarchy-pkg-drop omarchy-pkg-missing; do
  deploy_one "$n"
done

# --- 3) final summary ---
ok "Package management on apt:"
ok "  • Menu \u2192 'Install' → fzf over (apt-cache pkgnames) → sudo apt-get install -y"
ok "  • Menu \u2192 'Remove'  → fzf over (apt-mark showmanual) → sudo apt-get remove --purge -y"
ok "  • 90+ omarchy-install-X / omarchy-remove-X wrappers unchanged"
ok "Open the menu (Super+Space) and pick Install / Remove to test."
