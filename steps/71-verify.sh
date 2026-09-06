#!/usr/bin/env bash
# 71 — health check. Prints a pass/fail table; exits 1 if anything critical fails.
set -uo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

FAIL=0
check() { # check <label> <command that must exit 0>
  if eval "$2" >/dev/null 2>&1; then ok "$1"; else err "$1"; FAIL=1; fi
}
soft() {
  if eval "$2" >/dev/null 2>&1; then ok "$1"; else warn "$1 (optional)"; fi
}

log "binaries"
check "quickshell (qs)"        "command -v qs"
check "hyprland"               "command -v Hyprland || command -v hyprland"
soft  "xkbcli"                 "command -v xkbcli"
soft  "inotify-tools"          "command -v inotifywait"
soft  "jq"                     "command -v jq"
soft  "wpctl (wireplumber)"    "command -v wpctl"
soft  "nmcli"                  "command -v nmcli"
soft  "gum"                    "command -v gum"
soft  "brightnessctl"          "command -v brightnessctl"
soft  "wpaperd"                "command -v wpaperd"
soft  "wpaperctl"              "command -v wpaperctl"
soft  "hyprpaper (Arch prebuilt)" "command -v $HOME/.local/bin/hyprpaper && ldd $HOME/.local/bin/hyprpaper | grep -q 'libstdc++.so.6 => $HOME/.local/lib'"
soft  "hyprpaper-ws-switch.py" "[ -x '$HOME/bin/hyprpaper-ws-switch.py' ]"
soft  "hyprpaper XDG autostart" "[ -f '$HOME/.config/autostart/hyprpaper-autostart.desktop' ] && [ -f '$HOME/.config/autostart/hyprpaper-ws-switch-autostart.desktop' ]"
soft  "hyprpaper.conf"          "[ -f '$HOME/.config/hypr/hyprpaper.conf' ] && grep -q '^wallpaper' '$HOME/.config/hypr/hyprpaper.conf'"
soft  "ws1..ws5 pools"          "for n in 1 2 3 4 5; do [ -d \"$HOME/Pictures/wallpapers/ws\$n\" ] || exit 1; done"
soft  "GLIBC 2.43 math shim"    "[ -f '$HOME/.local/lib/libm-243-shim.so' ] && nm -D '$HOME/.local/lib/libm-243-shim.so' | grep -q 'sqrtf@GLIBC_2.43'"
soft  "wallpaper-rotate wrap"  "[ -x '$OMARCHY_HOME/bin/omarchy-wallpaper-rotate' ] || [ -x '$HOME/.local/bin/omarchy-wallpaper-rotate' ] || [ -x '$HOME/.local/share/omarchy/bin/omarchy-wallpaper-rotate' ]"

log "deployment"
check "omarchy payload"        "[ -d '$OMARCHY_HOME/shell' ] && [ -d '$OMARCHY_HOME/bin' ]"
check "omarchy-port launcher"  "[ -x '$HOME/.local/bin/omarchy-port' ]"
check "uwsm-app shim"          "[ -x '$OMARCHY_HOME/bin/uwsm-app' ]"
check "lock PAM service"       "[ -f /etc/pam.d/omarchy-lock-password ]"
# Menu definition ships with the payload (default/omarchy/) and may also be
# overridden per-user in ~/.config/omarchy/.
check "menu definition"        "[ -f '$OMARCHY_HOME/default/omarchy/omarchy-menu.jsonc' ] || [ -f '$HOME/.config/omarchy/omarchy-menu.jsonc' ]"
check "login-shell PATH"       "grep -rq 'omarchy/bin' '$HOME/.profile' 2>/dev/null"

log "fonts"
soft  "omarchy icon font"      "has omarchy fc-list"
soft  "Nerd Font"              "has nerd fc-list"
if command -v fc-match >/dev/null; then
  info "fc-match monospace -> $(fc-match monospace)"
fi

log "patches"
if grep -q "isTransient" "$OMARCHY_HOME/shell/plugins/notifications/Service.qml" 2>/dev/null; then
  ok "notifications isTransient"
else
  err "notifications isTransient (Qt 6.8 reserved word — notifications will break)"
  FAIL=1
fi
soft  "clock lunar Model.js"   "grep -q 'lunarInfo' '$OMARCHY_HOME/shell/plugins/panels/clock/Model.js'"
soft  "timezone via pkexec"    "grep -q 'pkexec' '$OMARCHY_HOME/bin/omarchy-menu-timezone'"

log "runtime"
if pgrep -x qs >/dev/null; then
  ok "quickshell running (pid $(pgrep -x qs | tr '\n' ' '))"
  if [ -n "${OMARCHY_HOME:-}" ] && command -v omarchy-shell >/dev/null; then
    PATH="$OMARCHY_HOME/bin:$PATH" omarchy-shell -q shell ping >/dev/null 2>&1 &&
      ok "IPC ping" || warn "IPC ping failed — is the shell wedged?"
  fi
else
  warn "quickshell not running — start with: ~/.local/bin/omarchy-port &"
fi

# Quick self-test of the lunar/term tables, when node is around
if [ "$WITH_CLOCK_ZH" = 1 ] && command -v node >/dev/null &&
   grep -q lunarInfo "$OMARCHY_HOME/shell/plugins/panels/clock/Model.js" 2>/dev/null; then
  log "lunar spot-check"
  node -e '
    const M = require(process.argv[1]);
    const t = new Date();
    const cases = [[2026,1,17,"春节"],[2026,1,16,"除夕"],[2026,8,7,"白露"],[2026,9,1,"国庆节"],[2026,4,1,"劳动节"]];
    let bad = 0;
    for (const [y,m,d,want] of cases) {
      const got = M.lunarDayLabel(y,m,d);
      if (got !== want) { console.log("  MISMATCH", `${y}-${m+1}-${d}`, got, "!=", want); bad++; }
    }
    console.log(bad ? "  lunar table BROKEN" : "  lunar table ok (5/5)");
    process.exit(bad ? 1 : 0);
  ' "$OMARCHY_HOME/shell/plugins/panels/clock/Model.js" || FAIL=1
fi

echo
[ "$FAIL" = 0 ] && ok "all critical checks passed" || err "some checks failed — see TROUBLESHOOTING.md"
exit "$FAIL"
