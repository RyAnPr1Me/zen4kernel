#!/bin/bash

# Exit immediately if a command exits with a non-zero status and fail on unset vars
set -euo pipefail
shopt -s nullglob

# Define directories
PATCH_DIR="kernel-patches"
KERNEL_DIR="linux"

# Set default kernel version
DEFAULT_KERNEL_VERSION="6.18.6"

# Check if the kernel directory exists
if [ ! -d "$KERNEL_DIR" ]; then
  echo "[INFO] Kernel source directory '$KERNEL_DIR' not found. Attempting to download."

  # Use provided version or default to 6.18
  KERNEL_VERSION="${1:-$DEFAULT_KERNEL_VERSION}"
  ARCHIVE_NAME="linux-$KERNEL_VERSION.tar.xz"
  DOWNLOAD_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_VERSION:0:1}.x/$ARCHIVE_NAME"

  echo "[INFO] Downloading Linux kernel version $KERNEL_VERSION from $DOWNLOAD_URL"
  if curl -o "$ARCHIVE_NAME" "$DOWNLOAD_URL"; then
    echo "[INFO] Download successful. Extracting archive."
    tar -xf "$ARCHIVE_NAME"
    mv "linux-$KERNEL_VERSION" "$KERNEL_DIR"
    rm "$ARCHIVE_NAME"
  else
    echo "[ERROR] Failed to download kernel source. Please check the version and try again."
    exit 1
  fi
fi

# Check if required tools are installed
for tool in patch make curl tar; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[ERROR] Required tool '$tool' is not installed. Please install it and try again."
    exit 1
  fi
done

# Normalize patch naming: sequential 0001-... ordering by filename sort
PATCHES_SORTED=($(ls -1 "$PATCH_DIR"/*.patch 2>/dev/null | sort))
if [ ${#PATCHES_SORTED[@]} -eq 0 ]; then
  echo "[ERROR] No patches found in $PATCH_DIR. Exiting."
  exit 1
fi

idx=1
for patch_path in "${PATCHES_SORTED[@]}"; do
  base=$(basename "$patch_path")
  stem=${base#*-}
  if [ "$stem" = "$base" ]; then
    stem=$base
  fi
  new_name=$(printf "%04d-%s" "$idx" "$stem")
  if [ "$new_name" != "$base" ]; then
    mv "$patch_path" "$PATCH_DIR/$new_name"
    patch_path="$PATCH_DIR/$new_name"
  fi
  PATCHES_SORTED[$((idx-1))]="$patch_path"
  idx=$((idx + 1))
done

# Apply patches in normalized order
PATCH_COUNT=0
for patch in "${PATCHES_SORTED[@]}"; do
  echo "[INFO] Applying patch: $patch"
  if patch -p1 -d "$KERNEL_DIR" < "$patch"; then
    echo "[INFO] Patch $patch applied successfully."
    PATCH_COUNT=$((PATCH_COUNT + 1))
  else
    echo "[WARNING] Failed to apply patch $patch. Skipping."
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