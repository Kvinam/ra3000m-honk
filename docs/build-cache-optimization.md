# Build cache policy and optimization notes

## Cache correctness rules

- Every source checkout is detached at the configured commit SHA and verifies `HEAD` before the build proceeds.
- OpenWrt and Honk Git object caches are separate from their working trees. Cache misses fetch the configured ref/commit; a failed cached checkout falls back to a clean direct checkout.
- Feed checkouts are reusable across source/config revisions. `scripts/update-feeds-cache.sh` resolves each configured Git feed's current remote revision and updates only feeds whose local `HEAD` differs. It always runs `feeds install -a` after source synchronization.
- The daeuniverse feed line is rewritten to the exact `HONK_COMMIT` pin, including replacement of stale or duplicate entries.
- OpenWrt `dl` archives are shared across source revisions. `make download` remains the authority for checksum verification and missing-file retrieval.
- APT indexes are cached only as a download optimization; `apt-get update` still runs on every build. Installed package versions are recorded in the artifact logs.
- ccache is shared across builds. ccache performs compiler/configuration checks; a cache hit is not assumed merely because an entry exists.
- Rust toolchains, bpf-linker archive, Cargo registry/Git data, host tools, toolchain and staging directories have separate cache scopes.

## Cache key and invalidation policy

| Cache | Restore scope | Correctness/invalidation |
|---|---|---|
| OpenWrt Git objects | Runner OS + repository | Checkout verifies `SOURCE_COMMIT`; fetches `SOURCE_REF` on a miss |
| Honk Git objects | Runner OS + repository | Checkout verifies `HONK_SOURCE_COMMIT` |
| Feeds | Runner OS | Per-feed remote revision check; invalid repositories are removed and recloned |
| OpenWrt `dl` | Runner OS | `make download` verifies checksums and downloads missing inputs |
| ccache | Runner OS | ccache compiler checks; capped at 5 GiB pending measured hit/eviction data |
| APT indexes | Ubuntu 24.04 runner | Index refresh still runs each build |
| APT archives | Ubuntu 24.04 + dependency-list hash | APT verifies package versions against current indexes |
| Rust toolchains | OS + pinned stable/nightly versions + target | rustup actions verify/install requested toolchains and components |
| bpf-linker | OS + version | SHA-256 checked; corrupt cached archive is discarded and downloaded again |
| Cargo registry/Git | OS + Cargo.lock hashes | Cargo validates lockfile package checksums and Git revisions |
| Staging/host tools/toolchain | OS + OpenWrt/overlay/Honk/feed/config fingerprints | Restore prefixes retain the full compatibility fingerprint; Honk source pin is included |

Legacy `dl` and feed cache prefixes are retained for migration. All save keys include the run ID because GitHub Actions caches are immutable. GitHub applies repository cache quotas and least-recently-used eviction; monitor the recorded footprints and avoid adding large target build trees that would evict higher-value caches. Restore prefixes deliberately omit the run ID so later runs can reuse the most recent compatible cache. Reports use `cache-matched-key`, not only `cache-hit`, because prefix restores are valid cache restores even when the exact-key flag is false.

## Deliberately not cached

- The full OpenWrt `build_dir/target-*` tree is not cached: it is large, toolchain/configuration sensitive, and risks restoring stale package build state.
- Generic Cargo `target/` output is not cached yet. The actual Honk/OpenWrt Cargo target locations and invalidation inputs must first be measured from a successful build; caching the wrong target tree can produce stale cross-compiled objects.
- ccache remains capped at 5 GiB until post-build statistics show sustained capacity pressure or eviction. The build log now records size, hit/miss counts and ccache log reasons to support that decision. Staging and host-tools archives also carry an explicit fingerprint manifest; the workflow discards a restored directory if that manifest does not match.

## Cache failure behavior

- Git cache repository corruption triggers one clean cache reinitialization; a failed local working-tree checkout falls back to a direct pinned checkout.
- A corrupted feed checkout is removed before the feed updater reclones it.
- A corrupted bpf-linker archive is rejected by SHA-256 and downloaded again.
- OpenWrt's download target remains responsible for missing or checksum-invalid source archives.
- Cache restore failure must never bypass commit, feed revision, configuration, BTF or firmware-artifact validation.

## Measurement

The firmware artifact logs include cache matched keys, cache footprints, feed commit manifest, APT package versions, ccache statistics/reason summary, download cache file counts and build phase timings. Individual restore/save durations remain available in the GitHub Actions step timings. Use these measurements before increasing cache size, adding Cargo target caches or changing compile/download concurrency.