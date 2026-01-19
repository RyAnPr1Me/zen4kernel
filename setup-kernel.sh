#!/bin/bash
set -e

# Zen4 Kernel Setup Script
# Optimized for AMD Ryzen 5 7600x + NVIDIA RTX 3050 + 32GB DDR5 + Wireless
# Maximum performance configuration

KERNEL_VERSION="6.18"
KERNEL_DIR="linux"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="${SCRIPT_DIR}/patches"

echo "========================================"
echo "Zen4 Kernel ${KERNEL_VERSION} Setup"
echo "========================================"
echo ""
echo "Target System:"
echo "  CPU: AMD Ryzen 5 7600x (Zen 4)"
echo "  GPU: NVIDIA RTX 3050"
echo "  RAM: 32GB DDR5"
echo "  Network: Wireless"
echo "  Goal: Maximum Performance"
echo ""

# Check if running as root
if [ "$EUID" -eq 0 ]; then 
   echo "ERROR: Do not run this script as root!"
   echo "Root privileges will be requested only when needed."
   exit 1
fi

# Check dependencies
echo "[1/7] Checking dependencies..."
DEPS=(base-devel clang lld llvm bc kmod libelf pahole cpio perl tar xz git wget)
MISSING_DEPS=()

for dep in "${DEPS[@]}"; do
    if ! pacman -Qi "$dep" &> /dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo "Missing dependencies: ${MISSING_DEPS[*]}"
    echo "Install them with:"
    echo "  sudo pacman -S ${MISSING_DEPS[*]}"
    exit 1
fi
echo "✓ All dependencies satisfied"

# Clone kernel if not exists
echo ""
echo "[2/7] Cloning Linux kernel ${KERNEL_VERSION}..."
if [ -d "${KERNEL_DIR}" ]; then
    echo "✓ Kernel directory already exists at ${KERNEL_DIR}"
else
    git clone --depth 1 --branch v${KERNEL_VERSION} https://github.com/torvalds/linux.git "${KERNEL_DIR}"
    echo "✓ Kernel cloned successfully"
fi

cd "${KERNEL_DIR}"

# Apply patches
echo ""
echo "[3/7] Applying performance patches..."

PATCH_ORDER=(
    "cachyos.patch"
    "dkms-clang.patch"
    "cloudflare.patch"
    "zen4-gaming-performance.patch"
)

for patch in "${PATCH_ORDER[@]}"; do
    echo "  → Applying ${patch}..."
    if patch -p1 --dry-run < "${PATCHES_DIR}/${patch}" &> /dev/null; then
        patch -p1 < "${PATCHES_DIR}/${patch}"
        echo "    ✓ ${patch} applied successfully"
    else
        echo "    ! ${patch} already applied or conflicts detected"
    fi
done

echo "✓ All patches applied"

# Copy or download base config
echo ""
echo "[4/7] Configuring kernel..."
if [ -f /proc/config.gz ]; then
    echo "  Using current system config as base..."
    zcat /proc/config.gz > .config
elif [ -f "${SCRIPT_DIR}/config" ]; then
    echo "  Using provided config file..."
    cp "${SCRIPT_DIR}/config" .config
else
    echo "  Downloading Arch Linux kernel config..."
    wget -q https://raw.githubusercontent.com/archlinux/svntogit-packages/packages/linux/trunk/config -O .config || {
        echo "  Warning: Could not download config, using defconfig"
        make defconfig
    }
fi

# Apply Zen4-specific optimizations
echo "  Applying Zen4 optimizations to .config..."

# Enable Zen4 processor support
scripts/config --enable CONFIG_MZEN4
scripts/config --disable CONFIG_GENERIC_CPU

# Performance governor
scripts/config --enable CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE
scripts/config --disable CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL

# AMD P-State EPP driver (best for Zen4)
scripts/config --enable CONFIG_X86_AMD_PSTATE
scripts/config --enable CONFIG_X86_AMD_PSTATE_DEFAULT_MODE_ACTIVE

# Preemption model - Preemptible Kernel (Low-Latency Desktop)
scripts/config --enable CONFIG_PREEMPT
scripts/config --disable CONFIG_PREEMPT_NONE
scripts/config --disable CONFIG_PREEMPT_VOLUNTARY

# Timer frequency - 1000 Hz for gaming
scripts/config --enable CONFIG_HZ_1000
scripts/config --set-val CONFIG_HZ 1000

# NVIDIA support
scripts/config --enable CONFIG_DRM
scripts/config --module CONFIG_DRM_NOUVEAU

# Wireless networking
scripts/config --enable CONFIG_WIRELESS
scripts/config --enable CONFIG_CFG80211
scripts/config --enable CONFIG_MAC80211
scripts/config --enable CONFIG_MAC80211_MESH

# TCP optimizations
scripts/config --enable CONFIG_TCP_CONG_BBR
scripts/config --enable CONFIG_TCP_CONG_WESTWOOD
scripts/config --set-str CONFIG_DEFAULT_TCP_CONG "bbr"

# Networking performance
scripts/config --enable CONFIG_NET_SCH_FQ
scripts/config --enable CONFIG_NET_SCH_FQ_CODEL

# NVMe optimizations
scripts/config --enable CONFIG_BLK_DEV_NVME
scripts/config --enable CONFIG_NVME_MULTIPATH

# USB performance (disable autosuspend is in patch)
scripts/config --enable CONFIG_USB_XHCI_HCD

# Huge pages for better memory performance
scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE
scripts/config --enable CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS

# Multi-Gen LRU (from CachyOS patch)
scripts/config --enable CONFIG_LRU_GEN
scripts/config --enable CONFIG_LRU_GEN_ENABLED

# Compiler optimizations
scripts/config --enable CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE
scripts/config --disable CONFIG_CC_OPTIMIZE_FOR_SIZE

# Reduce kernel log overhead
scripts/config --set-val CONFIG_LOG_BUF_SHIFT 18

# Enable BPF JIT for network performance
scripts/config --enable CONFIG_BPF_JIT
scripts/config --enable CONFIG_BPF_JIT_ALWAYS_ON

echo "✓ Kernel configured for Zen4 + NVIDIA + Gaming"

# Update config with new dependencies
echo ""
echo "[5/7] Running olddefconfig to update configuration..."
make olddefconfig

echo ""
echo "[6/7] Configuration complete!"
echo ""
echo "========================================"
echo "Build Commands:"
echo "========================================"
echo ""
echo "To build the kernel with Clang (recommended for Zen4):"
echo "  cd ${KERNEL_DIR}"
echo "  make -j\$(nproc) CC=clang LD=ld.lld LLVM=1"
echo ""
echo "Or with GCC (requires GCC 13+):"
echo "  cd ${KERNEL_DIR}"
echo "  make -j\$(nproc)"
echo ""
echo "To install (after successful build):"
echo "  sudo make modules_install"
echo "  sudo make install"
echo ""
echo "To update bootloader:"
echo "  sudo grub-mkconfig -o /boot/grub/grub.cfg"
echo "  # OR for systemd-boot:"
echo "  sudo bootctl update"
echo ""
echo "========================================"
echo "Optional: Configure kernel further"
echo "========================================"
echo ""
echo "Run 'make menuconfig' to customize:"
echo "  cd ${KERNEL_DIR}"
echo "  make menuconfig"
echo ""
echo "[7/7] Setup complete! Ready to build."
