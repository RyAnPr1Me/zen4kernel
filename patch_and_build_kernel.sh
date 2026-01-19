#!/bin/bash

# Exit immediately if a command exits with a non-zero status and fail on unset vars
set -euo pipefail
shopt -s nullglob

# Define directories
PATCH_DIR="kernel-patches"
KERNEL_DIR="linux"

# Arch Linux kernel source
ARCH_KERNEL_REMOTE="https://github.com/archlinux/linux.git"
DEFAULT_KERNEL_REF="master"

# Check if the kernel directory exists
if [ ! -d "$KERNEL_DIR" ]; then
  echo "[INFO] Kernel source directory '$KERNEL_DIR' not found. Cloning Arch Linux kernel source."

  KERNEL_REF="${1:-$DEFAULT_KERNEL_REF}"
  echo "[INFO] Cloning $ARCH_KERNEL_REMOTE (ref: $KERNEL_REF)"

  if git clone --depth 1 --branch "$KERNEL_REF" "$ARCH_KERNEL_REMOTE" "$KERNEL_DIR"; then
    echo "[INFO] Clone successful."
  else
    echo "[ERROR] Failed to clone Arch Linux kernel source. Please check the ref and try again."
    exit 1
  fi
fi

# Check if required tools are installed
for tool in patch make curl tar git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[ERROR] Required tool '$tool' is not installed. Please install it and try again."
    exit 1
  fi
done

# Build explicit patch order to avoid conflicting hunks while leaving patch contents untouched
PATCH_ORDER=(
  "$PATCH_DIR/cachyos.patch"
  "$PATCH_DIR/dkms-clang.patch"
  "$PATCH_DIR/zen4-gaming-performance.patch"
  "$PATCH_DIR/0001-XANMOD-x86-build-Prevent-generating-avx2-floating-po.patch"
  "$PATCH_DIR/0001-ZEN-input-evdev-Use-call_rcu-when-detaching-client.patch"
  "$PATCH_DIR/0001-netfilter-Add-netfilter-nf_tables-fullcone-support.patch"
  "$PATCH_DIR/0001-prjc-cachy-lfbmq.patch"
  "$PATCH_DIR/0001-sched-wait-Do-accept-in-LIFO-order-for-cache-efficie.patch"
  "$PATCH_DIR/0001-tcp-Add-a-sysctl-to-skip-tcp-collapse-processing-whe.patch"
  "$PATCH_DIR/0001-tcp_bbr-v3-update-TCP-bbr-congestion-control-module-.patch"
  "$PATCH_DIR/0002-XANMOD-x86-build-Add-LLVM-polyhedral-loop-optimizer-.patch"
  "$PATCH_DIR/0002-firmware-Enable-stateless-firmware-loading.patch"
  "$PATCH_DIR/0003-XANMOD-kbuild-Add-SMS-based-software-pipelining-flag.patch"
  "$PATCH_DIR/0003-locking-rwsem-spin-faster.patch"
  "$PATCH_DIR/0004-drivers-initialize-ata-before-graphics.patch"
  "$PATCH_DIR/0005-zen4-optimize-x86-flags.patch"
  "$PATCH_DIR/0007-zen4-aggressive-optimizations.patch"
  "$PATCH_DIR/0008-XANMOD-block-mq-deadline-Increase-write-priority-to-.patch"
  "$PATCH_DIR/0011-XANMOD-blk-wbt-Set-wbt_default_latency_nsec-to-2msec.patch"
  "$PATCH_DIR/0013-XANMOD-vfs-Decrease-rate-at-which-vfs-caches-are-rec.patch"
  "$PATCH_DIR/0016-XANMOD-sched-autogroup-Add-kernel-parameter-and-conf.patch"
)

# Collect patches: first the preferred order that exist, then any remaining sorted
PREFERRED_APPLY=()
declare -A seen
for p in "${PATCH_ORDER[@]}"; do
  if [ -f "$p" ]; then
    PREFERRED_APPLY+=("$p")
    seen["$p"]=1
  fi
done

EXTRA_PATCHES=($(ls -1 "$PATCH_DIR"/*.patch 2>/dev/null | sort))
if [ ${#EXTRA_PATCHES[@]} -eq 0 ]; then
  echo "[ERROR] No patches found in $PATCH_DIR. Exiting."
  exit 1
fi

APPLY_LIST=()
APPLY_LIST+=("${PREFERRED_APPLY[@]}")
for p in "${EXTRA_PATCHES[@]}"; do
  if [ -z "${seen[$p]:-}" ]; then
    APPLY_LIST+=("$p")
  fi
done

echo "[INFO] Patch application order:"
printf '  - %s\n' "${APPLY_LIST[@]}"

# Apply patches in the chosen order with pre-checks to avoid reapplying/reversing
PATCH_COUNT=0
for patch in "${APPLY_LIST[@]}"; do
  echo "[INFO] Applying patch: $patch"

  if patch -p1 --dry-run -N -d "$KERNEL_DIR" < "$patch" >/dev/null 2>&1; then
    if patch -p1 -N -d "$KERNEL_DIR" < "$patch"; then
      echo "[INFO] Patch $patch applied successfully."
      PATCH_COUNT=$((PATCH_COUNT + 1))
    else
      echo "[WARNING] Failed to apply patch $patch. Skipping."
    fi
  elif patch -p1 --dry-run -R -d "$KERNEL_DIR" < "$patch" >/dev/null 2>&1; then
    echo "[INFO] Patch $patch already applied (reverse would succeed). Skipping."
  else
    echo "[WARNING] Patch $patch does not apply cleanly. Skipping."
  fi

  echo
done

if [ "$PATCH_COUNT" -eq 0 ]; then
  echo "[ERROR] No patches were applied. Exiting."
  exit 1
fi

# Change to the kernel directory
cd "$KERNEL_DIR"

# Determine toolchain flags (prefer clang/ld.lld when present)
MAKE_FLAGS=(LOCALVERSION=-orion)
if command -v clang >/dev/null 2>&1 && command -v ld.lld >/dev/null 2>&1; then
  MAKE_FLAGS+=(LLVM=1 LLVM_IAS=1 LD=ld.lld CC=clang)
  echo "[INFO] Using LLVM toolchain."
else
  echo "[INFO] Using default GCC toolchain."
fi

# Absolute-max aggressive flags for Zen 4
MAX_OPTS="-O3 -march=znver4 -mtune=znver4 -flto=full -pipe"
MAX_OPTS+=" -falign-functions=32 -falign-jumps=1 -falign-loops=1"
MAX_OPTS+=" -fdevirtualize-at-ltrans"

MAKE_FLAGS+=(CFLAGS="$MAX_OPTS" CXXFLAGS="$MAX_OPTS" KCFLAGS="$MAX_OPTS")

# Clean the kernel build environment
make "${MAKE_FLAGS[@]}" clean
make "${MAKE_FLAGS[@]}" mrproper

# Configure the kernel (reuse existing config, then harden for speed)
make "${MAKE_FLAGS[@]}" olddefconfig

# Try to enable aggressive options when they exist; ignore if unavailable
for option in \
  "--disable LTO_NONE" \
  "--enable LTO_CLANG" \
  "--enable LTO_CLANG_FULL" \
  "--disable LTO_CLANG_THIN" \
  "--enable CC_OPTIMIZE_FOR_PERFORMANCE_O3" \
  "--enable CC_OPTIMIZE_FOR_PERFORMANCE" \
  "--disable CC_OPTIMIZE_FOR_SIZE"; do
  ./scripts/config $option || echo "[WARNING] Failed to set kernel config option: $option"
done

# Finalize config
make "${MAKE_FLAGS[@]}" localmodconfig
make xconfig
# Build the kernel
make "${MAKE_FLAGS[@]}" -j"$(nproc --all)"

# Install modules and kernel
if sudo make "${MAKE_FLAGS[@]}" modules_install && sudo make "${MAKE_FLAGS[@]}" install; then
  echo "[INFO] Kernel build and installation complete. Reboot your system to use the new kernel."
else
  echo "[ERROR] Kernel installation failed. Please check the logs."
  exit 1
fi

# Summary
echo "[INFO] Total patches applied: $PATCH_COUNT"