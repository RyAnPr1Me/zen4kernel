#!/bin/bash

# Exit immediately if a command exits with a non-zero status and fail on unset vars
set -euo pipefail
shopt -s nullglob

# Define directories
PATCH_DIR="kernel-patches"
KERNEL_DIR="linux"

# Check if the kernel directory exists
if [ ! -d "$KERNEL_DIR" ]; then
  echo "[ERROR] Kernel source directory '$KERNEL_DIR' not found. Exiting."
  exit 1
fi

# Check if required tools are installed
for tool in patch make; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "[ERROR] Required tool '$tool' is not installed. Please install it and try again."
    exit 1
  fi
done

# Apply patches
PATCH_COUNT=0
for patch in "$PATCH_DIR"/*.patch; do
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

# Add maximum optimization flags
MAKE_FLAGS+=(CFLAGS="-O3 -march=native -mtune=native -flto -pipe" CXXFLAGS="-O3 -march=native -mtune=native -flto -pipe")

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