#!/bin/bash

# Clean kernel build artifacts or remove the cloned source tree.
# Default: run "make clean mrproper" inside the linux tree if present.
# Use --distclean to delete the entire linux directory to force a fresh clone.

set -euo pipefail

KERNEL_DIR="linux"
DISTCLEAN=0

if [ "${1:-}" = "--distclean" ]; then
  DISTCLEAN=1
fi

if [ ! -d "$KERNEL_DIR" ]; then
  echo "[INFO] Kernel source directory '$KERNEL_DIR' not found; nothing to clean."
  exit 0
fi

if [ "$DISTCLEAN" -eq 1 ]; then
  echo "[INFO] Performing distclean: removing '$KERNEL_DIR' directory."
  rm -rf "$KERNEL_DIR"
  echo "[INFO] Distclean complete."
  exit 0
fi

if [ ! -f "$KERNEL_DIR/Makefile" ]; then
  echo "[WARNING] '$KERNEL_DIR' exists but does not look like a kernel tree; skipping make clean."
  exit 1
fi

pushd "$KERNEL_DIR" >/dev/null
make clean
make mrproper
popd >/dev/null

echo "[INFO] Kernel tree cleaned (make clean; make mrproper)."
