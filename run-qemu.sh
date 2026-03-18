#!/usr/bin/env bash
# run-qemu.sh — Launch a CTF kernel in QEMU with GDB stub
#
# Usage: bash run-qemu.sh [bzImage] [rootfs.cpio.gz]
#
# Defaults to looking for bzImage + rootfs.cpio.gz in $PWD
# GDB stub listens on :1234 (connect from Docker via host.docker.internal:1234)
#
# Install: brew install qemu

BZIMAGE="${1:-bzImage}"
ROOTFS="${2:-rootfs.cpio.gz}"

if [[ ! -f "$BZIMAGE" ]]; then
  echo "Error: kernel image not found: $BZIMAGE"
  exit 1
fi

if [[ ! -f "$ROOTFS" ]]; then
  echo "Error: initrd not found: $ROOTFS"
  exit 1
fi

# Common CTF kernel boot flags
# nokaslr    — disable KASLR (easier debugging; remove to test with KASLR)
# kpti=0     — disable KPTI (remove to test with KPTI)
# nopti      — same as kpti=0 on older kernels
# quiet      — suppress boot messages
# panic=1    — reboot 1s after kernel panic (useful for CTF)
# oops=panic — turn oopses into panics

APPEND="console=ttyS0 nokaslr kpti=0 nopti quiet panic=1 oops=panic"

echo "[*] Booting: $BZIMAGE + $ROOTFS"
echo "[*] GDB stub: localhost:1234 (Docker: host.docker.internal:1234)"
echo "[*] Connect:  gef> target remote host.docker.internal:1234"
echo ""

qemu-system-x86_64 \
  -kernel "$BZIMAGE" \
  -initrd "$ROOTFS" \
  -append "$APPEND" \
  -m 256M \
  -smp 2 \
  -cpu qemu64 \
  -nographic \
  -monitor /dev/null \
  -gdb tcp::1234 \
  -no-reboot \
  "$@"

# Variations:
#   -S                    → freeze CPU at startup, wait for GDB 'continue'
#   -cpu qemu64,+smep,+smap → enable SMEP/SMAP for realistic mitigation testing
#   -enable-kvm           → KVM acceleration (Linux host only, not available on Mac)
#   -snapshot             → discard disk writes on exit
