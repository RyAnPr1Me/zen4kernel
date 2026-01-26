#!/bin/bash
set -e

# Zen4 Kernel Installation Script
# Installs the built kernel to the system

KERNEL_DIR="linux"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "Zen4 Kernel Installation Script"
echo "========================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
   echo "ERROR: This script must be run as root!"
   echo "Please run: sudo ./install-kernel.sh"
   exit 1
fi

# Check if kernel directory exists
if [ ! -d "${KERNEL_DIR}" ]; then
    echo "ERROR: Kernel directory not found!"
    echo "Please run ./setup-kernel.sh and ./build-kernel.sh first"
    exit 1
fi

cd "${KERNEL_DIR}"

# Check if kernel was built
if [ ! -f arch/x86/boot/bzImage ]; then
    echo "ERROR: Kernel image not found!"
    echo "Please run ./build-kernel.sh first"
    exit 1
fi

echo "Installing kernel modules..."
make modules_install

echo ""
echo "Installing kernel image..."
make install

echo ""
echo "Updating bootloader configuration..."

# Detect bootloader
if [ -d /boot/grub ]; then
    echo "Detected GRUB bootloader"
    if command -v grub-mkconfig &> /dev/null; then
        grub-mkconfig -o /boot/grub/grub.cfg
        echo "✓ GRUB configuration updated"
    elif command -v grub2-mkconfig &> /dev/null; then
        grub2-mkconfig -o /boot/grub2/grub.cfg
        echo "✓ GRUB2 configuration updated"
    else
        echo "! Could not find grub-mkconfig, please update manually"
    fi
elif command -v bootctl &> /dev/null; then
    echo "Detected systemd-boot"
    bootctl update
    echo "✓ systemd-boot updated"
else
    echo "! Could not detect bootloader, please update manually"
fi

echo ""
echo "========================================"
echo "✓ Kernel installed successfully!"
echo "========================================"
echo ""
echo "IMPORTANT: Before rebooting, consider:"
echo ""
echo "1. Create boot parameters for optimal performance:"
echo "   Add to kernel command line (GRUB or systemd-boot):"
echo "     amd_pstate=active"
echo "     processor.max_cstate=1"
echo "     nvidia-drm.modeset=1"
echo "     nowatchdog"
echo "     nmi_watchdog=0"
echo ""
echo "2. For GRUB, edit /etc/default/grub:"
echo "   GRUB_CMDLINE_LINUX_DEFAULT=\"quiet amd_pstate=active processor.max_cstate=1 nvidia-drm.modeset=1\""
echo "   Then run: sudo grub-mkconfig -o /boot/grub/grub.cfg"
echo ""
echo "3. Reboot to use the new kernel:"
echo "   sudo reboot"
echo ""
