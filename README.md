![gdb-kernel-apple-silicon](https://socialify.git.ci/thePwn8/gdb-kernel-apple-silicon/image?custom_language=Dockerfile&description=1&language=1&name=1&owner=1&pattern=Brick+Wall&stargazers=1&theme=Light)

# GDB + bata24/gef for Linux Kernel Exploit Dev on Apple Silicon

> Full kernel exploit development environment for Mac M1/M2/M3/M4. Debug CTF kernels, find gadgets, build exploits.

---

## The Problem

Apple Silicon is ARM64. CTF kernels are x86_64. You need:

- **QEMU** to boot the x86_64 kernel on Mac
- **GDB** to connect to QEMU's GDB stub
- **bata24/gef** for kernel debug commands (`kbase`, `ksymaddr`, `pagewalk`, `slub-dump`)
- **Exploit dev tools** — ROP finders, pwntools, kernel image extractors

GDB connects to QEMU's GDB stub over TCP. No ptrace is involved. QEMU handles all CPU state inspection internally and exposes it via the GDB remote protocol.

> **Scope**: This does NOT solve userland debugging on Apple Silicon. Running `gdb ./binary` inside a QEMU-emulated Docker container will fail with `PTRACE_GETREGS: Input/output error` because QEMU's ptrace emulation is incomplete. Kernel debugging works because it bypasses ptrace entirely — QEMU *is* the CPU.

---

## What's Inside

### Installed by bata24/gef (don't duplicate)

| Tool | Purpose |
|------|---------|
| ropper | ROP gadget finder (Python) |
| rp++ | ROP gadget finder (C++, fast) |
| one_gadget | one-shot execve gadgets in libc |
| seccomp-tools | seccomp filter analysis |
| capstone | disassembly framework |
| keystone | assembler framework |
| unicorn | CPU emulator |
| angr | symbolic execution |

### Added by this Dockerfile

| Tool | Purpose |
|------|---------|
| **pwntools** | CTF framework — ROP builder, packing, tubes, shellcraft |
| **ROPgadget** | ROP gadget finder (different heuristics than ropper) |
| **ropr** | Rust-based ROP finder (fastest on large vmlinux) |
| **vmlinux-to-elf** | Recover kallsyms from stripped kernel → symbolized ELF |
| **extract-vmlinux** | Decompress bzImage → raw vmlinux |
| **musl-tools** | Static linking via musl (small binaries for initramfs) |
| **checksec** | Binary/kernel security properties |
| **nasm** | x86/x64 assembler for shellcode stubs |
| **pahole/dwarves** | Kernel struct layouts from BTF/DWARF |
| **strace** | Syscall tracing |
| **busybox-static** | Build minimal initramfs from scratch |
| **cpio + zstd** | Initrd repacking |

---

## Architecture

```
┌───────────────────────────────────────────────┐
│  Mac (Apple Silicon)                          │
│                                               │
│  qemu-system-x86_64          (ARM64 binary,   │
│    -kernel bzImage             TCG emulates   │
│    -initrd rootfs.cpio.gz      x86_64 guest)  │
│    -gdb tcp::1234       ◄─────────────────────┤── GDB stub
│                                               │       │
│  ┌─────────────────────────────────────────┐  │       │ TCP
│  │  Docker Container (linux/amd64)         │  │       │
│  │                                         │  │       │
│  │  gdb-multiarch + bata24/gef             │──┤───────┘
│  │  target remote host.docker.internal:1234│  │
│  └─────────────────────────────────────────┘  │
└───────────────────────────────────────────────┘
```

Homebrew's `qemu-system-x86_64` is a native ARM64 binary. It emulates the x86_64 guest via TCG. The `-gdb` flag exposes a GDB stub over TCP. GDB in Docker connects via `host.docker.internal` — no ptrace needed.

---

## Prerequisites

```bash
# QEMU (runs natively on ARM64 Mac — no Rosetta needed)
brew install qemu

# Docker Desktop for Mac
# https://docs.docker.com/desktop/install/mac-install/
```

---

## Build

```bash
docker build --platform=linux/amd64 -t gdb-gef .
```

Add to `~/.zshrc`:

```bash
alias pwn="docker run --rm -it \
  --security-opt seccomp=unconfined \
  --privileged \
  --cap-add=SYS_PTRACE \
  --platform=linux/amd64 \
  -v \$PWD:/data \
  --add-host=host.docker.internal:host-gateway \
  gdb-gef bash"
```

---

## Workflow

### Terminal 1 — Boot the kernel (Mac)

```bash
cd /path/to/ctf-challenge/
bash run-qemu.sh
```

`run-qemu.sh` launches QEMU with:

| Flag | Effect |
|------|--------|
| `nokaslr` | Disable KASLR — symbols resolve directly from vmlinux |
| `kpti=0 nopti` | Disable KPTI — cleaner kernel/user boundary |
| `-gdb tcp::1234` | GDB stub on port 1234 |
| `-cpu qemu64` | Base x86_64 CPU (add `+smep,+smap` for mitigation testing) |
| `-S` | (optional) Freeze CPU at boot, wait for GDB `continue` |

### Terminal 2 — Attach GDB (Docker)

```bash
cd /path/to/ctf-challenge/   # vmlinux must be here
pwn
```

Inside the container:

```bash
gef> file /data/vmlinux
gef> target remote host.docker.internal:1234
gef> c
```

---

## Kernel Image Workflow

CTF challenges ship `bzImage` (compressed, stripped). You need symbols for GDB.

```bash
# Step 1: Decompress bzImage → raw vmlinux
extract-vmlinux bzImage > vmlinux

# Step 2: Recover symbols from kallsyms (if stripped)
vmlinux-to-elf vmlinux vmlinux-sym

# Now load the symbolized ELF in GDB
gef> file /data/vmlinux-sym
gef> target remote host.docker.internal:1234
```

`vmlinux-to-elf` extracts the embedded kallsyms table and produces a fully symbolized ELF — the difference between blind exploitation and having function names in GDB.

---

## ROP Gadget Finding

Four finders included — each has different heuristics, use multiple for coverage:

```bash
# ropr — fastest on large vmlinux (Rust)
ropr --nojop vmlinux

# ROPgadget — broadest gadget search
ROPgadget --binary vmlinux --depth 20

# ropper — good filtering options
ropper -f vmlinux --search "pop rdi"

# rp++ — fast C++ finder
rp++ -f vmlinux -r 5
```

---

## bata24/gef Kernel Commands

```bash
# KASLR base (when nokaslr is NOT set)
gef> kbase

# Resolve kernel symbol address
gef> ksymaddr commit_creds
gef> ksymaddr prepare_kernel_cred

# Walk page tables (virt → phys)
gef> pagewalk 0xffffffff81000000

# SLUB allocator state — essential for heap exploitation
gef> slub-dump kmalloc-96
gef> slub-dump kmalloc-192

# Kernel security configuration
gef> kchecksec

# Loaded kernel modules
gef> lsmod
```

---

## Compiling Exploits

```bash
# Standard static build (glibc — larger binary)
gcc -o exploit exploit.c -static -O2

# musl static build (smaller, cleaner — preferred for initramfs)
musl-gcc -o exploit exploit.c -static -O2

# With specific kernel headers (if needed)
gcc -o exploit exploit.c -static -I/path/to/kernel/include
```

---

## Repacking initrd

After compiling your exploit, repack it into the initrd so the QEMU guest can run it:

```bash
# Unpack
mkdir /tmp/initrd && cd /tmp/initrd
zcat /path/to/rootfs.cpio.gz | cpio -idmv

# Add exploit
cp /data/exploit .

# Repack
find . | cpio -o -H newc | gzip > /data/rootfs_patched.cpio.gz

# Boot with patched initrd
bash run-qemu.sh bzImage rootfs_patched.cpio.gz
```

---

## Inspecting Kernel Structs

```bash
# pahole — show struct layout with offsets (needs vmlinux with DWARF/BTF)
pahole -C task_struct vmlinux
pahole -C cred vmlinux
pahole -C file vmlinux

# Show struct size
pahole -s vmlinux | grep msg_msg
```

---

## Mac Networking Gotcha

> `--network=host` on Docker Desktop for Mac attaches to the **Docker VM's** network — not your Mac's. `localhost:1234` inside the container points to the container itself, not QEMU on your Mac.
>
> Use `host.docker.internal:1234` to reach your Mac from inside a container.

This is why the `pwn` alias includes `--add-host=host.docker.internal:host-gateway`.

---

## Limitations

**Userland debugging is broken on Apple Silicon Docker.** Running `gdb ./binary` inside a `--platform=linux/amd64` container will fail:

```
warning: linux_ptrace_test_ret_to_nx: Cannot PTRACE_GETREGS: Input/output error
Couldn't get CS register: Input/output error.
```

This happens because the container runs under QEMU user-space emulation, and QEMU's ptrace emulation for child processes is incomplete. There is no clean workaround — this setup is for **kernel debugging only**.

For userland CTF challenges on Apple Silicon, use a Linux VM with full KVM or an x86_64 remote server.

---

## Troubleshooting

**`Connection refused` on `target remote host.docker.internal:1234`**
→ QEMU isn't running yet, or it crashed. Check Terminal 1.

**Symbols not resolving after `file vmlinux`**
→ Use `vmlinux-to-elf` to recover kallsyms. The raw `extract-vmlinux` output is often stripped.

**Kernel panic immediately on boot**
→ Try `init=/bin/sh` in APPEND to drop to shell directly.
→ Check `rootfs.cpio.gz` integrity: `file rootfs.cpio.gz`

**Docker build fails with permission error**
→ `sudo chown -R $(whoami) ~/.docker` — Docker Desktop sometimes creates buildx dirs as root.

---

## Repo Structure

```
.
├── Dockerfile          # Full kernel exploit dev environment
├── docker-compose.yml  # Alternative to alias
├── .gdbinit            # Kernel defaults (intel syntax, pagination off)
└── run-qemu.sh         # QEMU launcher with CTF-friendly boot flags
```

---

## References

- [bata24/gef](https://github.com/bata24/gef) — GDB Enhanced Features (kernel fork)
- [vmlinux-to-elf](https://github.com/marin-m/vmlinux-to-elf) — Recover symbols from stripped kernels
- [ropr](https://github.com/Ben-Lichtman/ropr) — Fast Rust ROP gadget finder
- [ROPgadget](https://github.com/JonathanSalwan/ROPgadget) — ROP gadget finder
- [pwntools](https://github.com/Gallopsled/pwntools) — CTF exploitation framework
- [QEMU GDB usage](https://qemu-project.gitlab.io/qemu/system/gdb.html)
