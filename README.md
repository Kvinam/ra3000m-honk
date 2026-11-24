# RAX3000M NAND + Honk Firmware

针对 **CMCC RAX3000M NAND 版** 的 ImmortalWrt 25.12 云编译配置与 Honk 集成工作区。

> 目标设备仅限 NAND 版本。eMMC 配置、分区表和镜像配方不得混用。

## 目标

- 目标平台：MediaTek Filogic
- 设备：CMCC RAX3000M NAND
- 固件基线：ImmortalWrt 25.12（源仓和设备定义待核实后锁定）
- Honk Full / Native API
- MTK 闭源 Wi-Fi 驱动与 HNAT/PPE、WED/WDMA 能力（以所选源码分支实际支持为准）
- IPv4/IPv6 硬件加速验证
- eBPF/TC、BTF、bpffs 支持
- GitHub Actions 手动触发云编译，构建产物归档

## Verified source baseline (initial pin)

- Config overlay: https://github.com/shiyu1314/openwrt-rax3000m, branch 25.12, commit 3e9480c061bcc92f6fa260920b189c22a6f04a9b
- Source tree: https://github.com/shiyu1314/openwrt-source, tag/ref v25.12.6, commit dc327b29f23cbee6c4dc41fef63656db0f7dba38
- Source branch/tag refs were checked with git ls-remote; files were inspected via GitHub API.

### Verified NAND device profile

- Device selector: CONFIG_TARGET_DEVICE_mediatek_filogic_DEVICE_cmcc_rax3000m-nand=y
- DTS: mt7981b-cmcc-rax3000m-nand.dts
- Overlay: mt7981b-cmcc-rax3000m-nand.dtso
- Image recipe: Device/cmcc_rax3000m-nand in target/linux/mediatek/image/filogic.mk
- Output type in recipe: sysupgrade.bin (sysupgrade-tar with metadata)
- NAND recipe parameters: UBINIZE_OPTS=-E 5, BLOCKSIZE=128k, PAGESIZE=2048, IMAGE_SIZE=116736k, kernel in UBI
- DTS overlay defines bl2, u-boot-env, factory, fip, and ubi partitions. bl2, factory, fip are marked read-only. UBI partition starts at 0x580000, size 0x7200000; these values are source-DTS evidence, not instructions to flash or repartition.

> These source pins are an initial baseline. Before building, verify that the refs still match and record the actual checkout commit. Do not flash based solely on this source inspection.

## 目录

- `config/`：固件配置片段
- `scripts/`：项目维护脚本
- `patches/`：必要且经过审查的补丁
- `.github/workflows/`：CI 云编译工作流

## 安全原则

1. 在确认源码仓库、分支和设备 profile 前，不开始正式构建。
2. 核对 NAND DTS、分区布局、设备镜像 recipe、升级/恢复流程。
3. 不引用 eMMC 设备 profile，不混用 NAND 与 eMMC 镜像。
4. 首次 Actions 工作流仅手动触发，并校验设备配置与产物；不自动刷机。
5. 任何刷写步骤都必须单独确认并验证恢复方案。

## 状态

- [x] 在本地目录初始化 Git 仓库（`main`）
- [x] 建立项目说明和忽略规则
- [ ] 确认并锁定可信源码仓及 25.12 分支/commit
- [ ] 从源码验证 RAX3000M NAND profile、DTS、分区与镜像 recipe
- [ ] 建立独立 diffconfig
- [ ] 配置 Honk Full 与 Native API
- [x] 建立手动触发的源码检查 GitHub Actions（仅检查，不构建）
- [ ] 验证构建产物与刷机恢复方案

## Build notes

构建由 `.github/workflows/build-firmware.yml` 执行。缓存架构、版本校验和回退策略见 [`docs/build-cache-optimization.md`](docs/build-cache-optimization.md)。

## Honk Full / BPF integration (configuration stage)

- Honk OpenWrt feed pinned to `daeuniverse/openwrt-packages` commit `e104a4930c5fc4f625f3355257626495685424f5`
- Selected: `honk`, `luci-app-honk`, `vmlinux-btf-builtin`, and TC/eBPF kernel modules
- Honk package build features: upstream defaults + `ebpf` + `native-ui`; native UI embeds Doona and implies Native API. The package source Makefile is pinned by feed commit, not copied into this repository.
- Kernel fragment: `config/kernel-bpf.fragment` enables BPF syscall/JIT, TC classifier/action, ingress, and veth. OpenWrt Kconfig enables full DWARF and BTF through `config/diffconfig` (`CONFIG_KERNEL_DEBUG_INFO=y`, `CONFIG_KERNEL_DEBUG_INFO_BTF=y`, reduced debug info disabled).
- Preparation script: `scripts/prepare-honk-build.sh` adds the pinned feed, applies the kernel config fragment idempotently, and installs Honk package definitions.

### Important BTF check

The router's running kernel was read-only checked: `/sys/kernel/btf/vmlinux` exists on kernel `6.6.95`. This proves the current running kernel has BTF, not that a future 6.12 build will. The build config enables BTF through OpenWrt Kconfig (`CONFIG_KERNEL_DEBUG_INFO_BTF=y`); the workflow verifies the generated Linux kernel `.config` and compiled `vmlinux` `.BTF` section. After the first boot, re-check `/sys/kernel/btf/vmlinux` before enabling Honk.

The new workflow `validate-honk-config.yml` performs feed preparation and `make defconfig` package-selection checks only. It does **not** build firmware or flash.


