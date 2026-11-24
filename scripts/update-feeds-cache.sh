#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CONFIG="${FEEDS_CONFIG:-feeds.conf.default}"
[[ -f "$CONFIG" ]] || { echo "ERROR: feed configuration not found: $CONFIG" >&2; exit 1; }
LOG="${FEEDS_UPDATE_LOG:-feeds-update.log}"
: > "$LOG"
log() { printf '%s\n' "$*" | tee -a "$LOG"; }
feed_count=0 updated=0 skipped=0 unsupported=0
while read -r type name spec _rest; do
  spec="${spec%$'\r'}"
  [[ -z "${type:-}" || "$type" == \#* ]] && continue
  case "$type" in
    src-git|src-git-full)
      feed_count=$((feed_count+1)); url="${spec%%^*}"; pin=""
      [[ "$spec" == *^* ]] && pin="${spec#*^}"
      local_dir="$ROOT/feeds/$name"; current=""
      if [[ -d "$local_dir/.git" || -f "$local_dir/.git" ]]; then
        current="$(git -C "$local_dir" rev-parse HEAD 2>/dev/null || true)"
        if [[ -n "$current" ]]; then
          if git -C "$local_dir" remote get-url origin >/dev/null 2>&1; then
            git -C "$local_dir" remote set-url origin "$url"
          else
            git -C "$local_dir" remote add origin "$url"
          fi
          # A matching HEAD is not sufficient if the restored worktree is damaged
          # or contains local tracked-file changes. Recreate it before reuse.
          if ! worktree_status="$(git -C "$local_dir" status --porcelain --untracked-files=no 2>/dev/null)"; then
            worktree_status=INVALID
          fi
          if [[ -n "$worktree_status" ]]; then
            log "WARNING: feed '$name' worktree is dirty or incomplete; removing it before update"
            rm -rf "$local_dir"
            current=""
          fi
        fi
      fi
      if [[ -z "$current" && -e "$local_dir" ]]; then
        log "WARNING: feed '$name' cache is invalid; removing it for a clean checkout"
        rm -rf "$local_dir"
      fi
      desired=""
      if [[ "$pin" =~ ^[0-9a-fA-F]{40}$ ]]; then
        desired="${pin,,}"
      else
        if [[ -n "$pin" ]]; then
          remote_refs="$(git ls-remote "$url" "refs/heads/$pin" "refs/tags/$pin" "refs/tags/$pin^{}")"
          desired="$(awk -v ref="refs/heads/$pin" '$2 == ref {print $1; exit}' <<< "$remote_refs")"
          if [[ -z "$desired" ]]; then desired="$(awk '$2 ~ /\^\{\}$/ {print $1; exit}' <<< "$remote_refs")"; fi
          if [[ -z "$desired" ]]; then desired="$(awk -v ref="refs/tags/$pin" '$2 == ref {print $1; exit}' <<< "$remote_refs")"; fi
        else
          remote_line="$(git ls-remote --symref "$url" HEAD | awk '$2 == "HEAD" && $1 != "ref:" {print; exit}')"
        fi
        if [[ -z "$pin" ]]; then desired="$(awk 'NR==1 {print $1}' <<< "$remote_line")"; fi
      fi
      if [[ -z "$desired" ]]; then log "ERROR: unable to resolve remote revision for feed '$name' ($url${pin:+^$pin})"; exit 1; fi
      if [[ "$current" == "$desired" ]]; then
        skipped=$((skipped+1)); log "UNCHANGED: feed '$name' already at $current; update skipped"
      else
        log "UPDATE: feed '$name' ${current:-<not cached>} -> $desired"
        ./scripts/feeds update "$name" 2>&1 | tee -a "$LOG"
        actual="$(git -C "$local_dir" rev-parse HEAD)"
        if [[ "$actual" != "$desired" ]]; then log "ERROR: feed '$name' resolved to $actual, expected $desired"; exit 1; fi
        updated=$((updated+1))
      fi
      ;;
    src-link) log "LOCAL: feed '${name:-unknown}' uses src-link; no Git update required" ;;
    *) unsupported=1; log "NOTICE: unsupported feed directive '$type'; falling back to update -a" ;;
  esac
done < "$CONFIG"
if [[ "$feed_count" -eq 0 || "$unsupported" -eq 1 ]]; then
  log "Running full feeds update for compatibility"
  ./scripts/feeds update -a 2>&1 | tee -a "$LOG"
  updated=all
fi
START=$SECONDS
./scripts/feeds install -a 2>&1 | tee feeds-install.log
log "Feeds summary: git_feeds=$feed_count updated=$updated unchanged=$skipped install_elapsed=$((SECONDS-START))s"
MANIFEST="$ROOT/.cache-feed-revisions"; TMP="${MANIFEST}.tmp"
{
  printf 'config-sha256 %s\n' "$(sha256sum "$CONFIG" | awk '{print $1}')"
  while IFS= read -r -d '' feed_dir; do
    feed_name="$(basename "$feed_dir")"
    if git -C "$feed_dir" rev-parse HEAD >/dev/null 2>&1; then printf '%s %s\n' "$feed_name" "$(git -C "$feed_dir" rev-parse HEAD)"; fi
  done < <(find feeds -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
} > "$TMP"
mv "$TMP" "$MANIFEST"; test -s "$MANIFEST"
log "Feed revision manifest:"; cat "$MANIFEST" | tee -a "$LOG"
