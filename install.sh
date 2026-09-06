#!/usr/bin/env bash
# omarchy-on-debian — run the Omarchy 4 (Quattro) shell on Debian 13 + Hyprland.
#
#   ./install.sh                 # full run
#   ./install.sh --dry-run       # print what would happen
#   ./install.sh --only 40       # run a single step
#   ./install.sh --src /path     # use a local checkout/tarball instead of cloning
#   WITH_CLOCK_ZH=0 ./install.sh # skip the Chinese lunar-calendar clock
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=lib/common.sh
. ./lib/common.sh

usage() {
  cat <<EOF
Usage: ./install.sh [options]
  --dry-run        show commands without changing anything
  --only N         run only step N (10|20|30|40|50|60|70)
  --from N         start at step N
  --src PATH       local Omarchy checkout or tarball (default: clone $OMARCHY_REPO)
  --no-clock-zh    skip the Chinese lunar/term clock extra
  -h, --help       this help
EOF
}

ONLY=""
FROM=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --only) ONLY="${2:?--only needs a step number}"; shift ;;
    --from) FROM="${2:?--from needs a step number}"; shift ;;
    --src) OMARCHY_SRC="${2:?--src needs a path}"; shift ;;
    --no-clock-zh) WITH_CLOCK_ZH=0 ;;
    -h|--help) usage; exit 0 ;;
    *) err "unknown option: $1"; usage; exit 1 ;;
  esac
  shift
done
export DRY_RUN WITH_CLOCK_ZH OMARCHY_SRC OMARCHY_HOME OMARCHY_WORK OMARCHY_REPO OMARCHY_BRANCH

STEPS=(steps/10-deps.sh steps/20-fetch.sh steps/30-deploy.sh steps/40-patch.sh
       steps/50-fonts.sh steps/60-hyprland.sh steps/65-about.sh steps/66-calculator.sh
       steps/67-monitor-scaling.sh steps/68-pkg-apt.sh steps/70-verify.sh)

log "omarchy-on-debian — target: $OMARCHY_HOME"
[ "$DRY_RUN" = 1 ] && warn "dry run: nothing will be changed"
[ -n "$OMARCHY_SRC" ] && info "source: $OMARCHY_SRC (local)"
[ "$WITH_CLOCK_ZH" = 1 ] && info "extras: Chinese lunar clock enabled"

for step in "${STEPS[@]}"; do
  num="$(basename "$step" | cut -d- -f1)"
  [ -n "$ONLY" ] && [ "$ONLY" != "$num" ] && continue
  [ -n "$FROM" ] && [ "$num" -lt "$FROM" ] 2>/dev/null && continue
  log "step $num — $(basename "$step" .sh | cut -d- -f2-)"
  bash "$step" || die "step $num failed (see above)"
done

log "done"
cat <<EOF

Next:
  1. Log out and back in (Hyprland autostart runs omarchy-port).
     Or start the shell now:  ~/.local/bin/omarchy-port &
  2. Super+D opens the Omarchy menu, Super+Alt+T the theme picker.
  3. If anything looks off:  ./steps/70-verify.sh
EOF
