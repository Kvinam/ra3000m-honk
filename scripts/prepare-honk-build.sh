#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FEED_FILE="$ROOT/feeds.conf.default"
HONK_COMMIT="${HONK_COMMIT:-e104a4930c5fc4f625f3355257626495685424f5}"
FEED_LINE="src-git daeuniverse https://github.com/daeuniverse/openwrt-packages^${HONK_COMMIT}"
KERNEL_CONFIG="$ROOT/target/linux/mediatek/filogic/config-6.12"
FRAGMENT="$ROOT/config/kernel-bpf.fragment"

if [[ ! -f "$FEED_FILE" ]]; then
  echo "ERROR: feeds.conf.default not found; run from an OpenWrt source checkout." >&2
  exit 1
fi
if [[ ! -f "$KERNEL_CONFIG" ]]; then
  echo "ERROR: Filogic 6.12 kernel config missing." >&2
  exit 1
fi

# Enforce the configured feed pin, replacing stale or duplicate daeuniverse entries.
FEED_TMP="$(mktemp)"
awk -v line="$FEED_LINE" '
  BEGIN { seen = 0 }
  /^[[:space:]]*src-git[[:space:]]+daeuniverse[[:space:]]/ {
    if (!seen) { print line; seen = 1 }
    next
  }
  { print }
  END { if (!seen) print line }
' "$FEED_FILE" > "$FEED_TMP"
if ! cmp -s "$FEED_TMP" "$FEED_FILE"; then mv "$FEED_TMP" "$FEED_FILE"; else rm -f "$FEED_TMP"; fi

while IFS= read -r setting; do
  [[ -z "$setting" || "$setting" == \#* ]] && continue
  symbol="${setting%%=*}"
  if grep -qE "^[[:space:]]*${symbol}=" "$KERNEL_CONFIG"; then
    continue
  elif grep -qE "^[[:space:]]*# ${symbol} is not set" "$KERNEL_CONFIG"; then
    sed -i "/^[[:space:]]*# ${symbol} is not set$/d" "$KERNEL_CONFIG"
  fi
  printf "%s\n" "$setting" >> "$KERNEL_CONFIG"
done < "$FRAGMENT"

echo "Pinned Honk feed ensured; BPF kernel fragment applied (BTF is configured through OpenWrt Kconfig)."
echo "Feed update/install and defconfig are handled by the workflow."
echo "This script does not compile or flash firmware."
