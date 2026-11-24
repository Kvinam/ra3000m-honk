#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 5 ]]; then echo "Usage: $0 <url> <tag> <sha> <bare-cache> <destination>" >&2; exit 2; fi
URL="$1" REF="$2" EXPECTED="$3" CACHE="$4" DEST="$5"
mkdir -p "$(dirname "$CACHE")" "$(dirname "$DEST")"
init_cache() {
  rm -rf "$CACHE"
  git init --bare "$CACHE"
  git --git-dir="$CACHE" remote add origin "$URL"
  git --git-dir="$CACHE" config remote.origin.promisor true
  git --git-dir="$CACHE" config remote.origin.partialclonefilter blob:none
  git --git-dir="$CACHE" config extensions.partialClone origin
}
if ! git --git-dir="$CACHE" rev-parse --is-bare-repository >/dev/null 2>&1; then
  init_cache
else
  if git --git-dir="$CACHE" remote get-url origin >/dev/null 2>&1; then
    git --git-dir="$CACHE" remote set-url origin "$URL"
  else
    git --git-dir="$CACHE" remote add origin "$URL"
  fi
fi
if ! git --git-dir="$CACHE" cat-file -e "${EXPECTED}^{commit}" 2>/dev/null; then
  echo "Git object cache miss for ${EXPECTED}; fetching pinned tag ${REF}"
  if ! git --git-dir="$CACHE" fetch --filter=blob:none --depth=1 origin "+refs/tags/${REF}:refs/tags/${REF}"; then
    echo "Cached Git repository unusable; rebuilding cache once"
    init_cache
    git --git-dir="$CACHE" fetch --filter=blob:none --depth=1 origin "+refs/tags/${REF}:refs/tags/${REF}"
  fi
fi
git --git-dir="$CACHE" cat-file -e "${EXPECTED}^{commit}"
rm -rf "$DEST"
if git clone --shared --no-checkout "$CACHE" "$DEST"; then
  git -C "$DEST" remote set-url origin "$URL"
  git -C "$DEST" config remote.origin.promisor true
  git -C "$DEST" config remote.origin.partialclonefilter blob:none
  git -C "$DEST" config extensions.partialClone origin
  if ! git -C "$DEST" checkout --detach "$EXPECTED"; then rm -rf "$DEST"; fi
fi
if [[ ! -d "$DEST/.git" ]]; then
  rm -rf "$DEST"
  echo "WARNING: local Git cache checkout failed; falling back to direct pinned-tag clone"
  git clone --filter=blob:none --no-checkout --depth=1 --branch "$REF" "$URL" "$DEST"
  git -C "$DEST" checkout --detach "$EXPECTED"
fi
ACTUAL="$(git -C "$DEST" rev-parse HEAD)"
test "$ACTUAL" = "$EXPECTED"
echo "PASS: pinned OpenWrt source ${ACTUAL}; Git object cache ${CACHE}"
