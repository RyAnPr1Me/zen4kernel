#!/bin/bash

# Exit immediately if a command exits with a non-zero status and fail on unset vars
set -euo pipefail
shopt -s nullglob

# Define directories
PATCH_DIR="kernel-patches"
KERNEL_DIR="linux"

# Check if the kernel directory exists
if [ ! -d "$KERNEL_DIR" ]; then
  echo "Kernel source directory '$KERNEL_DIR' not found. Exiting."
  exit 1
fi

# Apply patches
for patch in "$PATCH_DIR"/*.patch; do
  echo "Applying patch: $patch"
  patch -p1 -d "$KERNEL_DIR" < "$patch"
  echo "Patch $patch applied successfully."
  echo
done

# Change to the kernel directory
cd "$KERNEL_DIR"

# Determine toolchain flags (prefer clang/ld.lld when present)
MAKE_FLAGS=(LOCALVERSION=-orion)
if command -v clang >/dev/null 2>&1 && command -v ld.lld >/dev/null 2>&1; then
  MAKE_FLAGS+=(LLVM=1 LLVM_IAS=1 LD=ld.lld CC=clang)
fi

# Clean the kernel build environment
make "${MAKE_FLAGS[@]}" clean
make "${MAKE_FLAGS[@]}" mrproper

# Configure the kernel (reuse existing config, then harden for speed)
make "${MAKE_FLAGS[@]}" olddefconfig

# Try to enable aggressive options when they exist; ignore if unavailable
./scripts/config --disable LTO_NONE || true
./scripts/config --enable LTO_CLANG || true
./scripts/config --enable LTO_CLANG_FULL || true
./scripts/config --disable LTO_CLANG_THIN || true
./scripts/config --enable CC_OPTIMIZE_FOR_PERFORMANCE_O3 || true
./scripts/config --enable CC_OPTIMIZE_FOR_PERFORMANCE || true
./scripts/config --disable CC_OPTIMIZE_FOR_SIZE || true

# Finalize config
make "${MAKE_FLAGS[@]}" olddefconfig

# Build the kernel
make "${MAKE_FLAGS[@]}" -j"$(nproc --all)"

# Install modules and kernel
sudo make "${MAKE_FLAGS[@]}" modules_install
sudo make "${MAKE_FLAGS[@]}" install

# Notify the user
echo "Kernel build and installation complete. Reboot your system to use the new kernel."