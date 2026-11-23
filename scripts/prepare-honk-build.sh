#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
FEED_FILE="$ROOT/feeds.conf.default"
FEED_LINE="src-git daeuniverse https://github.com/daeuniverse/openwrt-packages^e104a4930c5fc4f625f3355257626495685424f5"
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

if ! grep -qE "^[[:space:]]*src-git[[:space:]]+daeuniverse[[:space:]]" "$FEED_FILE"; then
  printf "\n%s\n" "$FEED_LINE" >> "$FEED_FILE"
fi

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

./scripts/feeds update daeuniverse
./scripts/feeds install honk luci-app-honk vmlinux-btf-builtin

echo "Honk feed pinned and package definitions installed."
echo "BPF/BTF options appended idempotently to Filogic config-6.12."
echo "This script does not compile or flash firmware."