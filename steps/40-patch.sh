#!/usr/bin/env bash
# 40 — the Debian compatibility patches (idempotent; reverse-applied check first).
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

need_cmd patch
[ -d "$OMARCHY_HOME/shell" ] || die "nothing deployed at $OMARCHY_HOME — run step 30"

# Applied inside $OMARCHY_HOME with -p1, so patch paths (a/shell/... b/bin/...)
# line up with the deployed tree.
apply_patch() {
  local p="$1"
  local root
  case "$p" in
    *clock*|*notifications*) root="$OMARCHY_HOME" ;;
    *) root="$OMARCHY_HOME" ;;
  esac

  if [ "$DRY_RUN" = 1 ]; then
    printf '    %s[dry]%s patch -p1 -N -r- -d %s < %s\n' "$C_C" "$C_0" "$root" "$p"
    return 0
  fi

  # already applied? -R --dry-run succeeds when the reverse applies cleanly
  if patch -p1 -R --dry-run -f -d "$root" < "$p" >/dev/null 2>&1; then
    info "$(basename "$p") already applied"
    return 0
  fi

  if patch -p1 -N -r- -d "$root" < "$p"; then
    ok "applied $(basename "$p")"
  else
    warn "$(basename "$p") did not apply cleanly — merge it by hand (see TROUBLESHOOTING.md)"
    return 1
  fi
}

for p in patches/*.patch; do
  case "$p" in
    *clock-panel-zh*|*clock-barwidget-zh*)
      [ "$WITH_CLOCK_ZH" = 1 ] || { info "skipping $(basename "$p") (--no-clock-zh)"; continue; }
      ;;
  esac
  apply_patch "$p" || true
done

# --- Chinese lunar calendar: full replacement Model.js (adds lunarInfo +
#     termInfo tables and the label functions the patched QML calls).
if [ "$WITH_CLOCK_ZH" = 1 ]; then
  install_file extras/clock-zh/Model.js "$OMARCHY_HOME/shell/plugins/panels/clock/Model.js" 0644
  ok "clock Model.js (lunar + solar terms) installed"
fi

info "patches applied against upstream branch: $OMARCHY_BRANCH"
