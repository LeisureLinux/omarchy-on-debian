#!/usr/bin/env bash
# Step 69 — Show desktop (Super+D)
#
# This port adds a "minimize all → show desktop" toggle because the
# official Omarchy repo has no such script (Hyprland itself has no native
# minimize). Super+D was previously unbound on this layout.
#
# Behaviour (per hyprctl clients -j):
#   - Active workspace id is derived from clients -j (focusHistoryID min),
#     NOT from `activeworkspace -j`: on Hyprland 0.55 those return
#     sentinel values (id=-1337, name="active") and can't be trusted.
#   - Hide: collect every mapped, not-hidden, not-pinned, non-fullscreen
#     window on the active workspace, move each to special:hidden.
#     Hyprland 0.55.2 accepts `movetoworkspace special:hidden` but
#     *rejects* `movetoworksilent special:hidden` (Invalid dispatcher) —
#     we use the non-silent variant; the show-desktop call doesn't care
#     that focus follows the moving window, because we restore focus to
#     the workspace itself immediately after.
#   - Restore: read $STATE_FILE, look up the saved address only if it's
#     currently still on special:hidden (stale state is silently skipped),
#     then focus + move back to the original workspace.
#
# Idempotent: re-running on an already-deployed script is a no-op.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

BIN_SRC="$OMARCHY_HOME/bin/omarchy-show-desktop"
BIN_DST="$HOME/.local/share/omarchy/bin/omarchy-show-desktop"

# --- 1. Deploy script -------------------------------------------------------
mkdir -p "$(dirname "$BIN_DST")"

if [ ! -f "$BIN_SRC" ]; then
  die "missing source script at $BIN_SRC"
fi

if [ -f "$BIN_DST" ] && cmp -s "$BIN_SRC" "$BIN_DST"; then
  ok "omarchy-show-desktop already up to date"
else
  cp "$BIN_SRC" "$BIN_DST"
  chmod +x "$BIN_DST"
  ok "deployed omarchy-show-desktop -> $BIN_DST"
fi

# --- 2. Wire Super+D bind into ~/.config/hypr/hyprland.conf ----------------
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
if [ ! -f "$HYPR_CONF" ]; then
  warn "hyprland.conf not found at $HYPR_CONF — skipping bind injection"
  warn "Add this line manually inside your binds section:"
  warn "  bind = \$mainMod, D, exec, omarchy-show-desktop"
  exit 0
fi

if grep -qE '^\s*bind\s*=\s*\$mainMod\s*,\s*D\s*,\s*exec\s*,\s*omarchy-show-desktop' "$HYPR_CONF"; then
  ok "Super+D -> omarchy-show-desktop already bound in hyprland.conf"
else
  # Append right before the launching-apps section, next to other
  # workspace/panel binds (step 60 already injected a marker block).
  MARKER="# >>> omarchy-on-debian"
  if grep -q "^$MARKER" "$HYPR_CONF"; then
    # Insert before the marker block.
    tmp=$(mktemp)
    awk -v marker="$MARKER" -v new='bind = $mainMod, D, exec, omarchy-show-desktop  # Show desktop (toggle hide/restore active-ws windows)' '
      { print }
      $0 == marker && !done { print new; done=1 }
    ' "$HYPR_CONF" > "$tmp" && mv "$tmp" "$HYPR_CONF"
    ok "added Super+D -> omarchy-show-desktop bind (above port marker)"
  else
    echo '' >> "$HYPR_CONF"
    echo '# Show desktop (toggle hide/restore active-ws windows) — port step 69' >> "$HYPR_CONF"
    echo 'bind = $mainMod, D, exec, omarchy-show-desktop' >> "$HYPR_CONF"
    ok "appended Super+D -> omarchy-show-desktop bind"
  fi
  info "reload Hyprland to activate: hyprctl reload"
fi

# --- 3. Dependencies --------------------------------------------------------
for t in jq notify-send hyprctl; do
  if ! command -v "$t" >/dev/null 2>&1; then
    warn "missing dependency: $t — install before Super+D will work"
  fi
done