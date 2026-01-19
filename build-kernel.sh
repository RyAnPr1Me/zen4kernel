#!/bin/bash
set -e

# Zen4 Kernel Build Script
# High-performance build for AMD Ryzen 5 7600x

KERNEL_DIR="linux"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "Zen4 Kernel Build Script"
echo "========================================"
echo ""

# Check if kernel directory exists
if [ ! -d "${KERNEL_DIR}" ]; then
    echo "ERROR: Kernel directory not found!"
    echo "Please run ./setup-kernel.sh first"
    exit 1
fi

cd "${KERNEL_DIR}"

# Check if .config exists
if [ ! -f .config ]; then
    echo "ERROR: .config not found!"
    echo "Please run ./setup-kernel.sh first"
    exit 1
fi

# Determine compiler
USE_CLANG=1
if ! command -v clang &> /dev/null; then
    echo "WARNING: Clang not found, falling back to GCC"
    USE_CLANG=0
fi

# Get CPU count
NCPUS=$(nproc)
echo "Building with ${NCPUS} parallel jobs"
echo ""

# Build kernel
if [ $USE_CLANG -eq 1 ]; then
    echo "Building with Clang + LLD (optimized for Zen4)..."
    echo "This will take approximately 10-30 minutes depending on your system..."
    echo ""
    time make -j${NCPUS} CC=clang LD=ld.lld LLVM=1 2>&1 | tee build.log
else
    echo "Building with GCC..."
    echo "This will take approximately 10-30 minutes depending on your system..."
    echo ""
    time make -j${NCPUS} 2>&1 | tee build.log
fi

# Check if build was successful
if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "✓ Build completed successfully!"
    echo "========================================"
    echo ""
    echo "Kernel image: $(ls -lh arch/x86/boot/bzImage)"
    echo ""
    echo "To install the kernel:"
    echo "  sudo make modules_install"
    echo "  sudo make install"
    echo ""
    echo "Or use the install script:"
    echo "  sudo ./install-kernel.sh"
    echo ""
else
    echo ""
    echo "========================================"
    echo "✗ Build failed!"
    echo "========================================"
    echo ""
    echo "Check build.log for details"
    exit 1
fi
