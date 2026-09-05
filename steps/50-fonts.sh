#!/usr/bin/env bash
# 50 — fonts. Two separate problems, two separate fixes.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

# 1) The launcher glyph (U+E900) is NOT a Nerd Font glyph — it lives in
#    omarchy's own icon font, which the Arch package installs and we must too.
SRC="$(cat "$OMARCHY_WORK/.src-root" 2>/dev/null || echo "")"
[ -z "$SRC" ] && [ -n "${OMARCHY_SRC:-}" ] && SRC="$OMARCHY_SRC"
[ -z "$SRC" ] && SRC="$OMARCHY_WORK/src"
FONT_DIR="$HOME/.local/share/fonts/omarchy"
if [ -f "$SRC/default/fonts/omarchy/omarchy.ttf" ]; then
  run mkdir -p "$FONT_DIR"
  run cp "$SRC/default/fonts/omarchy/omarchy.ttf" "$FONT_DIR/"
  ok "omarchy.ttf installed (launcher + agent icons)"
else
  warn "omarchy.ttf not found in source — launcher icon will be a tofu box"
fi

# 2) monospace must resolve to a Nerd Font, or Qt falls back to something like
#    Sun-ExtA (no PUA glyphs) and the weather icons render as garbage.
#    `prefer` is too weak here: Sun-ExtA's language score wins under a zh locale.
install_file dotfiles/61-nerd-font-monospace.conf \
  "$HOME/.config/fontconfig/conf.d/61-nerd-font-monospace.conf" 0644

run fc-cache -f >/dev/null
ok "font cache rebuilt"

if command -v fc-match >/dev/null; then
  info "fc-match monospace -> $(fc-match monospace)"
  info "fc-match omarchy   -> $(fc-match omarchy)"
fi
