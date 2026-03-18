# GDB + bata24/gef — Linux Kernel Exploit Development on Apple Silicon
#
# Build:  docker build --platform=linux/amd64 -t gdb-gef .
# Use:    alias pwn="docker run --rm -it \
#           --security-opt seccomp=unconfined \
#           --privileged \
#           --cap-add=SYS_PTRACE \
#           --platform=linux/amd64 \
#           -v \$PWD:/data \
#           --add-host=host.docker.internal:host-gateway \
#           gdb-gef bash"
#
# Kernel debug workflow:
#   Terminal 1 (Mac):       bash run-qemu.sh
#   Terminal 2 (container): pwn
#                           gef> file /data/vmlinux
#                           gef> target remote host.docker.internal:1234
#
# NOTE: This container is for KERNEL debugging via QEMU's GDB stub (TCP).
#       Userland debugging (ptrace-based) does NOT work reliably on Apple Silicon
#       due to QEMU's incomplete ptrace emulation in Docker.

FROM --platform=linux/amd64 ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Enable 32-bit (i386) multiarch — for compiling 32-bit exploits
RUN dpkg --add-architecture i386

# ── Base system + build tools ────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    # Core
    git \
    vim \
    curl \
    wget \
    file \
    sudo \
    unzip \
    colordiff \
    # Build
    gcc \
    gcc-multilib \
    make \
    build-essential \
    nasm \
    musl-tools \
    # Python
    python3 \
    python3-dev \
    # Ruby (for gef's one_gadget / seccomp-tools)
    ruby-dev \
    ruby \
    # Debugging
    gdb \
    gdb-multiarch \
    binutils \
    binutils-multiarch \
    checksec \
    strace \
    # Kernel struct inspection (pahole for BTF/DWARF struct layouts)
    dwarves \
    # Initrd repacking
    cpio \
    zstd \
    busybox-static \
    # 32-bit support
    libc6:i386 \
    libc6-dev-i386 \
    libstdc++6:i386 \
    && rm -rf /var/lib/apt/lists/*

# ── bata24/gef ───────────────────────────────────────────────────────
# Installs: ropper, rp++, one_gadget, seccomp-tools, capstone,
#           keystone, unicorn, angr — DO NOT duplicate these.
# Kernel commands: kbase, ksymaddr, pagewalk, slub-dump, kchecksec
# Full list: https://github.com/bata24/gef#features
RUN wget -q https://raw.githubusercontent.com/bata24/gef/dev/install-uv.sh -O- | sudo sh

# ── Kernel exploit dev tools ─────────────────────────────────────────

# pwntools — CTF framework (ROP builder, packing, tubes, shellcraft)
# ROPgadget — ROP gadget finder (different heuristics than ropper)
# vmlinux-to-elf — recover kallsyms from stripped kernel → symbolized ELF
RUN pip3 install --no-cache-dir --break-system-packages \
    pwntools \
    ROPgadget \
    lz4 zstandard \
    && pip3 install --no-cache-dir --break-system-packages \
    git+https://github.com/marin-m/vmlinux-to-elf

# extract-vmlinux — decompress bzImage → raw vmlinux
RUN wget -O /usr/local/bin/extract-vmlinux \
    https://raw.githubusercontent.com/torvalds/linux/master/scripts/extract-vmlinux \
    && chmod +x /usr/local/bin/extract-vmlinux

# ropr — fast Rust-based ROP gadget finder (x86/x64 targets)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
    && . /root/.cargo/env \
    && cargo install ropr \
    && cp /root/.cargo/bin/ropr /usr/local/bin/ \
    && rm -rf /root/.cargo/registry /root/.cargo/git

# ── GDB config ───────────────────────────────────────────────────────

# Default kernel .gdbinit
COPY .gdbinit /root/.gdbinit.kernel
# bata24/gef installer writes its own /root/.gdbinit — append our kernel defaults
RUN echo "" >> /root/.gdbinit && cat /root/.gdbinit.kernel >> /root/.gdbinit

WORKDIR /data
CMD ["/bin/bash"]
