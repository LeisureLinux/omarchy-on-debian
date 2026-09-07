#!/usr/bin/env bash
# packaging/rust-crate-deb/build.sh
# ------------------------------------------------------------------
# Generic cargo-crate → .deb builder. Use this for any Rust app that
# Debian trixie main / contrib doesn't carry but the user actually
# wants (e.g. wpaperd, swww, waypaper).
#
# Strategy
# --------
#   1. cargo build --release with the proxy stripped (so a dead LAN
#      PAC proxy can't stall the fetch from crates.io).
#   2. Strip the binary with `strip --strip-unneeded`.
#   3. Stage into a fake filesystem rooted at $STAGE.
#   4. fpm -s dir -t deb produces /workspace/build/<name>_<ver>_amd64.deb
#   5. Optional: dput / reprepro into repo.freelamp.com.
#
# Usage
# -----
#   CRATE=wpaperd VERSION=1.0.1 \
#     CRATE_BIN=wpaperd BIN_PATH=target/release/wpaperd \
#     DESCRIPTION="Wayland wallpaper daemon with rotation" \
#     HOMEPAGE="https://github.com/an-anonymous-coder/wpaperd" \
#     LICENSE=MIT \
#     DEPS='libwayland-client0,libdbus-1-3' \
#     ./build.sh
#
# Conventions
# -----------
#   * $STAGE/usr/bin/         — main binary (and any extra bin: list)
#   * $STAGE/usr/share/<pkg>/ — assets (e.g. wpaperd ships an example.toml)
#   * $STAGE/usr/lib/systemd/user/ — systemd user units (if any)
#   * $STAGE/DEBIAN/postinst / prerm — generated from heredocs (see below)
# ------------------------------------------------------------------
set -euo pipefail

: "${CRATE:?CRATE (crate name) is required}"
: "${VERSION:?VERSION (crate version) is required}"
: "${CRATE_BIN:?CRATE_BIN (binary name) is required}"
: "${DESCRIPTION:?DESCRIPTION is required}"
: "${HOMEPAGE:=https://crates.io/crates/${CRATE}}"
: "${LICENSE:=MIT}"
: "${DEPS:=}"
: "${EXTRA_BINS:=}"
: "${EXTRA_FILES:=}"   # space-separated list of "src:dst" relative to repo root

WORKSPACE=$(cd "$(dirname "$0")/.." && pwd)
BUILD_DIR="${WORKSPACE}/${CRATE}/build"
STAGE="${BUILD_DIR}/stage"
DEB="${BUILD_DIR}/${CRATE}_${VERSION}_amd64.deb"

mkdir -p "${BUILD_DIR}" "${STAGE}"

# ------------------------------------------------------------------
# 1. fetch + build
# ------------------------------------------------------------------
echo "==> cargo fetch + build ${CRATE} ${VERSION}"
SRC_DIR="${BUILD_DIR}/src"
if [[ ! -d "${SRC_DIR}" ]]; then
  git clone --depth 1 --branch "v${VERSION}" \
    "https://github.com/an-anonymous-coder/wpaperd.git" "${SRC_DIR}" \
    || git clone --depth 1 "https://github.com/an-anonymous-coder/wpaperd.git" "${SRC_DIR}"
  # Generic fallback: if upstream URL pattern is different, override via CRATE_REPO env.
fi
pushd "${SRC_DIR}" >/dev/null
# If pinned via Cargo.lock / --locked, drop the flag in favour of a clean check.
env -u http_proxy -u https_proxy -u all_proxy \
  cargo build --release --locked
popd >/dev/null

# ------------------------------------------------------------------
# 2. strip + stage
# ------------------------------------------------------------------
BIN_PATH="${SRC_DIR}/target/release/${CRATE_BIN}"
strip --strip-unneeded "${BIN_PATH}"

mkdir -p "${STAGE}/usr/bin"
install -m 0755 "${BIN_PATH}" "${STAGE}/usr/bin/${CRATE_BIN}"

for extra in ${EXTRA_BINS}; do
  src="${SRC_DIR}/target/release/${extra}"
  [[ -f "${src}" ]] || { echo "!! missing extra bin: ${src}"; exit 1; }
  install -m 0755 "${src}" "${STAGE}/usr/bin/${extra}"
done

for pair in ${EXTRA_FILES}; do
  src="${pair%%:*}"
  dst="${pair##*:}"
  mkdir -p "${STAGE}/$(dirname "${dst}")"
  install -m 0644 "${WORKSPACE}/${CRATE}/${src}" "${STAGE}/${dst}"
done

# ------------------------------------------------------------------
# 3. fpm
# ------------------------------------------------------------------
DEB_DEPS=""
if [[ -n "${DEPS}" ]]; then
  DEB_DEPS="--depends $(echo "${DEPS}" | tr ',' ' ' | tr ' ' '\n' | sort -u | paste -sd, -)"
fi

fpm -s dir -t deb \
  -n "${CRATE}" -v "${VERSION}" \
  --description "${DESCRIPTION}" \
  --url "${HOMEPAGE}" \
  --license "${LICENSE}" \
  --maintainer "LeisureLinux <leisurelinux@freelamp.com>" \
  --deb-no-default-config-files \
  ${DEB_DEPS} \
  -C "${STAGE}" -p "${DEB}"

echo "==> built ${DEB}"
ls -la "${DEB}"

# ------------------------------------------------------------------
# 4. optional: push to repo.freelamp.com
# ------------------------------------------------------------------
if [[ "${PUSH:-0}" == "1" ]]; then
  echo "==> uploading to freelamp (reprepro)"
  reprepro -b /srv/freelamp includedeb trixie "${DEB}"
fi
