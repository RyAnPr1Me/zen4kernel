#!/bin/bash

# Kernel Optimization Verification Script
# Checks if all optimizations were applied correctly

echo "==========================================="
echo "Zen4 Kernel Optimization Verification"
echo "==========================================="
echo ""

KERNEL_DIR="linux"
ERRORS=0
WARNINGS=0

# Check if kernel directory exists
if [ ! -d "$KERNEL_DIR" ]; then
    echo "❌ ERROR: Kernel directory not found!"
    echo "   Run ./setup-kernel.sh first"
    exit 1
fi

cd "$KERNEL_DIR"

echo "[1/10] Checking CPU-specific optimizations..."
if grep -q "march=znver4" Makefile; then
    echo "  ✓ Zen4 compiler flags present in Makefile"
else
    echo "  ❌ Zen4 compiler flags NOT found"
    ((ERRORS++))
fi

if grep -q "mavx512" Makefile; then
    echo "  ✓ AVX-512 flags enabled"
else
    echo "  ⚠ AVX-512 flags not found"
    ((WARNINGS++))
fi

echo ""
echo "[2/10] Checking AMD CPU prefetcher optimizations..."
if grep -q "0xC0011020" arch/x86/kernel/cpu/amd.c; then
    echo "  ✓ DC prefetcher MSR modifications present"
else
    echo "  ❌ Prefetcher optimizations NOT applied"
    ((ERRORS++))
fi

echo ""
echo "[3/10] Checking scheduler optimizations..."
if grep -q "350000ULL" kernel/sched/fair.c; then
    echo "  ✓ Reduced scheduler base slice (350µs)"
else
    echo "  ⚠ Scheduler base slice not optimized"
    ((WARNINGS++))
fi

if grep -q "250000UL" kernel/sched/fair.c; then
    echo "  ✓ Reduced migration cost (250µs)"
else
    echo "  ⚠ Migration cost not optimized"
    ((WARNINGS++))
fi

echo ""
echo "[4/10] Checking memory management..."
if grep -q "vm_swappiness = 10" mm/vmscan.c; then
    echo "  ✓ Swappiness reduced to 10"
else
    echo "  ⚠ Swappiness not optimized"
    ((WARNINGS++))
fi

echo ""
echo "[5/10] Checking network optimizations..."
if grep -q "32\*1024" net/ipv4/tcp.c && grep -q "262144" net/ipv4/tcp.c; then
    echo "  ✓ TCP buffer sizes increased"
else
    echo "  ⚠ TCP buffers not optimized"
    ((WARNINGS++))
fi

echo ""
echo "[6/10] Checking PCIe optimizations..."
if grep -q "pcie_set_mps.*512" drivers/pci/probe.c; then
    echo "  ✓ PCIe MPS set to 512"
else
    echo "  ❌ PCIe MPS optimization NOT found"
    ((ERRORS++))
fi

if grep -q "PCI_EXP_DEVCTL_RELAX_EN" drivers/pci/probe.c; then
    echo "  ✓ PCIe relaxed ordering enabled"
else
    echo "  ⚠ Relaxed ordering not found (may be OK)"
    ((WARNINGS++))
fi

echo ""
echo "[7/10] Checking LLVM optimizations..."
if grep -q "polly" Makefile; then
    echo "  ✓ LLVM Polly optimizer enabled"
else
    echo "  ⚠ Polly optimizer not found (OK for GCC builds)"
    ((WARNINGS++))
fi

echo ""
echo "[8/10] Checking applied patches..."
PATCHES_APPLIED=0

if grep -q "Zen 4: Prefer same L3 cache" kernel/sched/fair.c; then
    echo "  ✓ zen4-gaming-performance.patch applied"
    ((PATCHES_APPLIED++))
fi

if grep -q "TCP collapse optimization" net/ipv4/tcp_input.c 2>/dev/null; then
    echo "  ✓ cloudflare.patch applied"
    ((PATCHES_APPLIED++))
fi

if grep -q "CONFIG_CACHY" mm/vmscan.c; then
    echo "  ✓ cachyos.patch (partial) applied"
    ((PATCHES_APPLIED++))
fi

if grep -q "fs_initcall(ata_init)" drivers/ata/libata-core.c; then
    echo "  ✓ ATA-before-graphics optimization applied"
    ((PATCHES_APPLIED++))
fi

echo "  → Total patches applied: $PATCHES_APPLIED/4"

echo ""
echo "[9/10] Checking kernel config..."
if [ -f .config ]; then
    echo "  ✓ .config exists"
    echo "  → NOTE: CPU type doesn't matter - Makefile forces znver4"
    
    if grep -q "CONFIG_X86_AMD_PSTATE=y\|CONFIG_X86_AMD_PSTATE=m" .config; then
        echo "  ✓ AMD P-State driver enabled"
    else
        echo "  ⚠ AMD P-State not enabled (will enable in setup)"
        ((WARNINGS++))
    fi
else
    echo "  ❌ .config not found - run setup script first"
    ((ERRORS++))
fi

echo ""
echo "[10/10] Checking for compilation blockers..."

# Check compiler version
if command -v clang &> /dev/null; then
    CLANG_VER=$(clang --version | head -1 | grep -oP '\d+' | head -1)
    if [ "$CLANG_VER" -ge 16 ]; then
        echo "  ✓ Clang $CLANG_VER detected (Polly supported)"
    else
        echo "  ⚠ Clang $CLANG_VER too old (need 16+), Polly disabled"
        ((WARNINGS++))
    fi
else
    echo "  ⚠ Clang not found, will use GCC"
    ((WARNINGS++))
fi

if command -v gcc &> /dev/null; then
    GCC_VER=$(gcc -dumpversion | cut -d. -f1)
    if [ "$GCC_VER" -ge 13 ]; then
        echo "  ✓ GCC $GCC_VER detected (znver4 supported)"
    else
        echo "  ❌ GCC $GCC_VER too old (need 13+ for znver4)"
        ((ERRORS++))
    fi
fi

echo ""
echo "==========================================="
echo "Verification Summary"
echo "==========================================="
echo ""

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo "✅ All optimizations applied successfully!"
    echo ""
    echo "Ready to build:"
    echo "  ./build-kernel.sh"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo "✅ Core optimizations applied"
    echo "⚠  $WARNINGS warning(s) found (non-critical)"
    echo ""
    echo "You can proceed with building:"
    echo "  ./build-kernel.sh"
    exit 0
else
    echo "❌ $ERRORS error(s) found"
    echo "⚠  $WARNINGS warning(s) found"
    echo ""
    echo "Please fix errors before building."
    exit 1
fi
