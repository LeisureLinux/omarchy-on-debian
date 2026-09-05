#!/usr/bin/env bash
# Shared helpers. Sourced by install.sh and every step.
# shellcheck shell=bash

OMARCHY_HOME="${OMARCHY_HOME:-$HOME/.local/share/omarchy}"
OMARCHY_SRC="${OMARCHY_SRC:-}"          # local checkout or tarball; empty = clone from GitHub
OMARCHY_REPO="${OMARCHY_REPO:-https://github.com/omacom/omarchy}"
OMARCHY_BRANCH="${OMARCHY_BRANCH:-quattro}"
OMARCHY_WORK="${OMARCHY_WORK:-$HOME/.cache/omarchy-on-debian}"
STATE_DIR="$OMARCHY_HOME/.omarchy-on-debian"

DRY_RUN="${DRY_RUN:-0}"
WITH_CLOCK_ZH="${WITH_CLOCK_ZH:-1}"

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_B=$'\033[1m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_C=$'\033[36m'; C_0=$'\033[0m'
else
  C_B=""; C_G=""; C_Y=""; C_R=""; C_C=""; C_0=""
fi

log()  { printf '%s==>%s %s\n' "$C_B" "$C_0" "$*"; }
info() { printf '    %s\n' "$*"; }
ok()   { printf '  %sok%s %s\n' "$C_G" "$C_0" "$*"; }
warn() { printf '  %swarn%s %s\n' "$C_Y" "$C_0" "$*" >&2; }
err()  { printf '  %serr%s %s\n' "$C_R" "$C_0" "$*" >&2; }
die()  { err "$*"; exit 1; }

run() {
  if [ "$DRY_RUN" = 1 ]; then printf '    %s[dry]%s %s\n' "$C_C" "$C_0" "$*"; else "$@"; fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

# has <pattern> <command [args…]> — true if the command's output matches.
# Never pipe into `grep -q` under `set -o pipefail`: the producer gets SIGPIPE
# (exit 141) the moment grep -q exits, and pipefail reports that as failure —
# so a *successful* match looks like a miss. grep -c drains the input instead.
has() {
  local pat="$1"; shift
  "$@" 2>/dev/null | grep -ci -- "$pat" >/dev/null 2>&1
}

# Copy a file, keeping a one-shot backup of whatever was there.
install_file() {
  local src="$1" dest="$2" mode="${3:-0644}"
  if [ -e "$dest" ] && ! cmp -s "$src" "$dest"; then
    run mkdir -p "$STATE_DIR/backups"
    run cp -a "$dest" "$STATE_DIR/backups/$(basename "$dest").$(date +%s).bak"
    info "backed up existing $(basename "$dest")"
  fi
  run mkdir -p "$(dirname "$dest")"
  run cp "$src" "$dest"
  run chmod "$mode" "$dest"
}

# Append a guarded block to a file only if the marker is not present yet.
append_once() {
  local file="$1" marker="$2" content="$3"
  if [ -e "$file" ] && grep -qF "$marker" "$file" 2>/dev/null; then
    info "$(basename "$file") already patched (marker found)"
    return 0
  fi
  [ "$DRY_RUN" = 1 ] && { printf '    %s[dry]%s append block to %s\n' "$C_C" "$C_0" "$file"; return 0; }
  mkdir -p "$(dirname "$file")"
  printf '\n%s\n' "$content" >> "$file"
  ok "patched $file"
}
