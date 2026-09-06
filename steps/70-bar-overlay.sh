#!/usr/bin/env bash
# Step 70 — Keep top bar visible above fullscreen windows
#
# The upstream Omarchy 4 (Quattro) Quickshell bar binds itself to
# WlrLayer.Top (Hyprland layer level 2). Above that sits WlrLayer.Overlay
# (level 3), which is the ONLY layer drawn on top of fullscreen windows.
# So whenever Super+F (or any other path) issues `dispatch fullscreen 1`
# on a tiled window, the bar slides offscreen.
#
# Fix: change the bar's WlrLayershell.layer from Top to Overlay. The bar
# becomes part of the overlay group; fullscreen apps show under it. This
# matches what users coming from Windows / macOS / KDE expect when they
# press F11 / Cmd+Ctrl+F.
#
# Hyprland's `layerrule` cannot move a layersurface between layer levels —
# only the client (Quickshell, here) chooses its own layer. So this has
# to be patched in the QML, not in hyprland.conf.
#
# Idempotent:
#   - Already-patched Bar.qml (containing the Overlay marker comment)
#     is skipped on re-run.
#   - The single-line replacement is safe to re-apply if the upstream
#     default ever drifts back.
#
# Persistence note: steps/30-deploy.sh overwrites Bar.qml with whatever
# ships in omarchy-src. After a `git pull` of omarchy-src you must
# re-run `bash steps/70-bar-overlay.sh` to reapply this patch.
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

BAR="$OMARCHY_HOME/shell/plugins/bar/Bar.qml"
[ -f "$BAR" ] || die "not found: $BAR (install Quickshell first)"

# Quickshell/QML uses // for comments. We pick the same form for our marker
# so injecting it next to the layer line doesn't break the QML parser.
MARKER='// port-step-70: keep bar on top of fullscreen windows'
TARGET='WlrLayershell.layer: WlrLayer.Overlay'
OLD='WlrLayershell.layer: WlrLayer.Top'

# Already patched? grep for the marker comment near the layer line.
if grep -qF "$MARKER" "$BAR"; then
  ok "Bar.qml already on Overlay layer (marker found)"
  exit 0
fi

if ! grep -qF "$OLD" "$BAR"; then
  warn "expected upstream line not found in Bar.qml:"
  warn "  $OLD"
  warn "omarchy-src may have drifted. Patching manually is safer; aborting."
  exit 1
fi

# One-shot backup kept forever (next install would otherwise overwrite),
# per the install_file convention in lib/common.sh.
BAK="$STATE_DIR/backups/Bar.qml.$(date +%s).bak"
run mkdir -p "$STATE_DIR/backups"
run cp -a "$BAR" "$BAK"
info "backed up Bar.qml -> $BAK"

# Replace the bar's layer line in-place AND inject the marker right after
# it so re-runs and upstream upgrades can both be detected. We use sed
# anchored at the unique namespace above it so an accidentally equal
# string elsewhere in the file (the -drag-ghost / -move-ghost surfaces
# on lines 1183/1245 are also Overlay) won't be touched.
tmp=$(mktemp)
sed -i.bak \
  -e '/WlrLayershell.namespace: "omarchy-bar"$/,+1 {
        s|WlrLayershell.layer: WlrLayer\.Top|WlrLayershell.layer: WlrLayer.Overlay\n'"$MARKER"'|
      }' "$BAR"
# Drop the .bak (we keep our own timestamped copy at $BAK).
rm -f "$BAR.bak"
ok "patched Bar.qml: $OLD  -->  $TARGET"

info "reload Quickshell to activate: kill the running qs instance"
info "(e.g. pkill -f 'qs -p' or qs kill --path \"$OMARCHY_HOME/shell\")"
info "Hyprland does NOT need a reload."
