#!/usr/bin/env bash
# 20 — get the Omarchy source into $OMARCHY_WORK/src (shell/, bin/, config/, default/, themes/).
set -euo pipefail
cd "$(dirname "$0")/.."
. ./lib/common.sh

need_cmd rsync
run mkdir -p "$OMARCHY_WORK"

SRC="$OMARCHY_WORK/src"
if [ -d "$SRC/shell" ] && [ -d "$SRC/bin" ]; then
  ok "source already at $SRC (set OMARCHY_SRC or delete it to refetch)"
  exit 0
fi

case "${OMARCHY_SRC:-}" in
  "") # fresh clone — shallow, single branch
      need_cmd git
      info "cloning $OMARCHY_REPO ($OMARCHY_BRANCH)"
      run git clone --depth 1 --branch "$OMARCHY_BRANCH" "$OMARCHY_REPO" "$SRC" ;;
  *.tar.gz|*.tgz)
      info "extracting $OMARCHY_SRC"
      run mkdir -p "$SRC"
      run tar xzf "$OMARCHY_SRC" -C "$SRC" --strip-components=1 ;;
  *)  info "copying local checkout $OMARCHY_SRC"
      run mkdir -p "$SRC"
      run rsync -a "$OMARCHY_SRC"/ "$SRC"/ ;;
esac

# The upstream layout keeps the install payload under install/omarchy/;
# when using a tarball of the repo root, descend into it.
for probe in shell bin config default themes; do
  if [ ! -e "$SRC/$probe" ] && [ -d "$SRC/install/omarchy/$probe" ]; then
    info "found payload under install/omarchy/ — using that as source root"
    run rsync -a "$SRC/install/omarchy"/ "$OMARCHY_WORK/payload"/
    SRC="$OMARCHY_WORK/payload"
    break
  fi
done

for probe in shell bin config default themes; do
  [ -d "$SRC/$probe" ] || warn "source missing $probe/ — some steps will be partial"
done
ok "source ready: $SRC"
run mkdir -p "$OMARCHY_WORK"
[ "$DRY_RUN" = 1 ] || printf '%s\n' "$SRC" > "$OMARCHY_WORK/.src-root"
