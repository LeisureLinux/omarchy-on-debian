#!/usr/bin/env bash
# Step 72 — Install Quickshell lock-screen PAM service files.
#
# Without /etc/pam.d/omarchy-lock-password, Quickshell's lock plugin sees
# passwordPamConfigured=false, the IPC `lock lock` call returns
# `missing-pam`, and Super+Ctrl+L silently does nothing. Upstream Omarchy's
# `install/config/lockscreen-pam.sh` writes this service but it relies on
# Arch-only modules (pam_systemd_home.so, system-local-login). Debian ships
# none of those, so this step writes a Debian-native equivalent.

set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

command -v apt-get >/dev/null || die "this step expects apt (Debian/Ubuntu)"

need_sudo() { command -v sudo >/dev/null && echo sudo || echo; }
SUDO="$(need_sudo)"
[ -z "$SUDO" ] && [ "$(id -u)" -ne 0 ] && die "need root or sudo to install /etc/pam.d files"

# pam_unix needs libpam-modules (already pulled in by hyprlock/swaylock), but
# be defensive in case a future image is missing it.
command -v pam_tally2 >/dev/null || true  # legacy, ignore
[ -f /usr/lib/x86_64-linux-gnu/security/pam_unix.so ] \
  || run $SUDO apt-get install -y --no-install-recommends libpam-modules
[ -f /usr/lib/x86_64-linux-gnu/security/pam_faillock.so ] \
  || run $SUDO apt-get install -y --no-install-recommends libpam-modules

PAM_PASSWORD_FILE=/etc/pam.d/omarchy-lock-password
run $SUDO tee "$PAM_PASSWORD_FILE" >/dev/null <<'PAM_EOF'
#%PAM-1.0
# Lock-screen password authentication for Quickshell's omarchy.lock plugin.
# Debian-compatible: Arch-only modules (pam_systemd_home.so,
# system-local-login) are intentionally omitted. pam_unix handles both
# password verification and account validity here.
auth       required                    pam_faillock.so preauth silent deny=10 unlock_time=120
auth       [success=1 default=bad]     pam_unix.so try_first_pass nullok
auth       optional                    pam_permit.so
auth       required                    pam_env.so
auth       required                    pam_faillock.so authsucc
account    required                    pam_unix.so
session    required                    pam_unix.so
PAM_EOF
run $SUDO chmod 644 "$PAM_PASSWORD_FILE"

# --- optional: fingerprint
# libpam-fprintd ships pam_fprintd.so on Debian. We register the file only
# when both the module and a fprintd-registered finger are present;
# otherwise remove any stale file so the plugin's FileView watcher will
# report load failure for fingerprint (intended — password fallback).
PAM_FP_FILE=/etc/pam.d/omarchy-lock-fingerprint
if [ -f /usr/lib/x86_64-linux-gnu/security/pam_fprintd.so ] \
   && command -v fprintd-list >/dev/null \
   && fprintd-list "${SUDO_USER:-${OMARCHY_INSTALL_USER:-${USER}}}" 2>/dev/null | grep -qi finger; then
  run $SUDO tee "$PAM_FP_FILE" >/dev/null <<'PAM_FP_EOF'
#%PAM-1.0
auth       required                    pam_fprintd.so
account    required                    pam_unix.so
PAM_FP_EOF
  run $SUDO chmod 644 "$PAM_FP_FILE"
  ok "fingerprint enrolled: $PAM_FP_FILE"
else
  if [ -f "$PAM_FP_FILE" ]; then
    run $SUDO rm -f "$PAM_FP_FILE"
    info "no fingerprint enrolled — removed stale $PAM_FP_FILE"
  else
    info "no fingerprint enrolled — $PAM_FP_FILE not created"
  fi
fi

# Allow hyprlock/swaylock to also run from a TTY without our new file
# colliding with the system `login` service. They already include the
# standard Debian modules, so nothing to do beyond existence check.
[ -f /etc/pam.d/login ] || warn "/etc/pam.d/login missing — login via TTY may break"

# Restart the running shell so FileView re-reads the new files.
if command -v omarchy-restart-shell >/dev/null 2>&1 && omarchy-shell lock status >/dev/null 2>&1; then
  run omarchy-restart-shell || true
fi

ok "lock-screen PAM service installed"
[ "$(id -u)" -eq 0 ] || info "test now: Super+Ctrl+L (Super+Ctrl+I toggles idle lock)"
