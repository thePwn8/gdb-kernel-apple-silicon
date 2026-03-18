# GDB + bata24/gef — Linux Kernel Debugging on Apple Silicon
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

RUN apt-get update && apt-get install -y \
    git \
    vim \
    curl \
    wget \
    file \
    python3 \
    python3-dev \
    binutils \
    binutils-multiarch \
    gdb \
    gdb-multiarch \
    ruby-dev \
    ruby \
    gcc \
    gcc-multilib \
    make \
    unzip \
    colordiff \
    sudo \
    libc6:i386 \
    libc6-dev-i386 \
    libstdc++6:i386 \
    && rm -rf /var/lib/apt/lists/*

# Install bata24/gef
# Key kernel debug commands: kbase, ksymaddr, pagewalk, slub-dump, kchecksec
# Full list: https://github.com/bata24/gef#features
RUN wget -q https://raw.githubusercontent.com/bata24/gef/dev/install-uv.sh -O- | sudo sh

# Default kernel .gdbinit
COPY .gdbinit /root/.gdbinit.kernel
# bata24/gef installer writes its own /root/.gdbinit — append our kernel defaults
RUN echo "" >> /root/.gdbinit && cat /root/.gdbinit.kernel >> /root/.gdbinit

WORKDIR /data
CMD ["/bin/bash"]
