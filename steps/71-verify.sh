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
# Wallpaper stack — wpaperd carries the load (step 73); the per-workspace
# switcher + state file + tooling all live under step 74.
soft  "wpaperd"                "command -v wpaperd || command -v $HOME/.local/bin/wpaperd"
soft  "wpaperctl"              "command -v wpaperctl || command -v $HOME/.local/bin/wpaperctl"
soft  "wpaperd-ws-switch.py"   "[ -x '$HOME/bin/wpaperd-ws-switch.py' ]"
soft  "wpaperd-ws state file"  "[ -f '$HOME/.local/state/wpaperd-ws-state.json' ]"
soft  "wallpaper source dir"   "[ -d '$HOME/Pictures/wallpapers' ]"
soft  "wallpaper-rotate wrap"  "[ -x '$OMARCHY_HOME/bin/omarchy-wallpaper-rotate' ] || [ -x '$HOME/.local/bin/omarchy-wallpaper-rotate' ] || [ -x '$HOME/.local/share/omarchy/bin/omarchy-wallpaper-rotate' ]"
soft  "wpaperd running"        "pgrep -x wpaperd >/dev/null"
soft  "ws-switcher running"    "pgrep -f '$HOME/bin/wpaperd-ws-switch.py' >/dev/null"

log "lock chain (step 74 time-bomb defusal)"
if [[ -f /etc/pam.d/hyprlock ]]; then
  # Inspect the file *minus* its comments so the explanatory header
  # in the omarchy-on-debian override doesn't trip the second grep.
  non_comment="$(grep -vE '^\s*#' /etc/pam.d/hyprlock || true)"
  if grep -q "^auth.*pam_unix" <<<"$non_comment" && ! grep -q "pam_ecryptfs" <<<"$non_comment"; then
    ok "/etc/pam.d/hyprlock is the omarchy-on-debian override (pam_unix only)"
  elif [[ -f /etc/pam.d/hyprlock.bak-omarchy-on-debian ]]; then
    ok "/etc/pam.d/hyprlock was replaced (.bak present)"
  else
    err "/etc/pam.d/hyprlock still inherits pam_ecryptfs (compositor crash risk)"
    FAIL=1
  fi
else
  warn "/etc/pam.d/hyprlock absent (hyprlock not installed?)"
fi
if command -v systemctl >/dev/null; then
  state="$(systemctl --user is-enabled xdg-desktop-portal-hyprland.service 2>&1 || true)"
  if [[ "$state" == "masked" || "$state" == "static" ]]; then
    ok "xdg-desktop-portal-hyprland.service is masked (no screencopy segfault)"
  else
    err "xdg-desktop-portal-hyprland.service is NOT masked — locks will crash"
    FAIL=1
  fi
fi

log "wallpaper config"
if [[ -f "$HOME/.config/wpaperd/wallpaper.toml" ]]; then
  if grep -qE '^\[(eDP-1|DP-4)\]' "$HOME/.config/wpaperd/wallpaper.toml"; then
    err "wpaperd config has stale monitor-specific blocks — re-run step 73 for a generic config"
    FAIL=1
  elif grep -q '^\[any\]' "$HOME/.config/wpaperd/wallpaper.toml"; then
    ok "wpaperd config is generic ([any] → ~/Pictures/wallpapers)"
  else
    warn "wpaperd config present but has no [any] fallback section"
  fi
else
  warn "no wpaperd config yet (run step 73)"
fi
if [[ -f "$HOME/.config/hypr/hyprland.conf" ]]; then
  if grep -qE '^exec-once *= *[/\$A-Za-z._-]*wpaperd' "$HOME/.config/hypr/hyprland.conf"; then
    ok "hyprland.conf: exec-once = wpaperd (live daemon)"
  else
    warn "hyprland.conf missing exec-once = wpaperd (rely on XDG autostart only)"
  fi
  if grep -qE 'loginctl lock-session' "$HOME/.config/hypr/hyprland.conf"; then
    ok "hyprland.conf: Super+Ctrl+L → loginctl lock-session"
  fi
fi

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
