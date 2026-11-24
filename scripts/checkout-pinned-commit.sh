#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 4 ]]; then echo "Usage: $0 <url> <sha> <bare-cache> <destination>" >&2; exit 2; fi
URL="$1" EXPECTED="$2" CACHE="$3" DEST="$4"
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
  echo "Honk Git object cache miss for ${EXPECTED}; fetching exact commit"
  if ! git --git-dir="$CACHE" fetch --filter=blob:none --depth=1 origin "$EXPECTED"; then
    echo "Cached Honk Git repository unusable; rebuilding cache once"
    init_cache
    git --git-dir="$CACHE" fetch --filter=blob:none --depth=1 origin "$EXPECTED"
  fi
fi
git --git-dir="$CACHE" cat-file -e "${EXPECTED}^{commit}"
rm -rf "$DEST"
if git clone --no-checkout "$CACHE" "$DEST"; then
  git -C "$DEST" remote set-url origin "$URL"
  git -C "$DEST" config remote.origin.promisor true
  git -C "$DEST" config remote.origin.partialclonefilter blob:none
  git -C "$DEST" config extensions.partialClone origin
  if ! git -C "$DEST" checkout --detach "$EXPECTED"; then rm -rf "$DEST"; fi
fi
if [[ ! -d "$DEST/.git" ]]; then
  rm -rf "$DEST"
  echo "WARNING: local Honk Git cache checkout failed; falling back to direct pinned-commit fetch"
  git clone --filter=blob:none --no-checkout "$URL" "$DEST"
  git -C "$DEST" fetch --filter=blob:none --depth=1 origin "$EXPECTED"
  git -C "$DEST" checkout --detach "$EXPECTED"
fi
ACTUAL="$(git -C "$DEST" rev-parse HEAD)"
test "$ACTUAL" = "$EXPECTED"
echo "PASS: Honk source pinned at ${ACTUAL}"
