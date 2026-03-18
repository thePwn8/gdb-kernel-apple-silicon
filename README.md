# GDB + bata24/gef for Linux Kernel Debugging on Apple Silicon

> Minimal setup for debugging CTF kernels and writing kernel exploits on Mac M1/M2/M3/M4.

---

## The Problem

Apple Silicon is ARM64. CTF kernels are x86_64. You need:

- **QEMU** to boot the x86_64 kernel on Mac
- **GDB** to connect to QEMU's GDB stub
- **bata24/gef** for kernel debug commands (`kbase`, `ksymaddr`, `pagewalk`, `slub-dump`)

This setup is specifically for **kernel debugging** — GDB connects to QEMU's GDB stub over TCP. No ptrace is involved between GDB and the target. QEMU handles all CPU state inspection internally and exposes it via the GDB remote protocol.

> **Scope**: This does NOT solve userland debugging on Apple Silicon. Running `gdb ./binary` inside a QEMU-emulated Docker container will fail with `PTRACE_GETREGS: Input/output error` because QEMU's ptrace emulation is incomplete. Kernel debugging works because it bypasses ptrace entirely — QEMU *is* the CPU.

---

## Why bata24/gef?

[bata24/gef](https://github.com/bata24/gef) is a fork of GEF that adds kernel-specific features:

- **Kernel debugging without symbols** — debug Linux kernels 3.x–6.x without a symbolized `vmlinux`
- **SLUB/SLAB heap analysis** — `slub-dump`, `slub-tiny-dump` for kernel heap exploitation
- **KASLR handling** — `kbase` to find the kernel base under KASLR
- **Page table walking** — `pagewalk` for virtual-to-physical translation
- **Pre-installed tools** — `one_gadget`, `seccomp-tools`, `ropper`, `angr`, `rp++`, `capstone`, `unicorn`, `keystone`

For kernel exploitation work, it's the most complete GDB setup available.

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

**How it works**: Homebrew's `qemu-system-x86_64` is a native ARM64 binary. It emulates the x86_64 guest CPU via TCG (Tiny Code Generator). The `-gdb` flag exposes a GDB stub over TCP. GDB in Docker connects to this stub via `host.docker.internal` — no ptrace syscalls are needed. QEMU owns the CPU state and serves it over the GDB remote protocol.

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

## Getting vmlinux from bzImage

CTF challenges usually ship `bzImage` (compressed). GDB needs the unstripped `vmlinux` for symbols:

```bash
curl -sO https://raw.githubusercontent.com/torvalds/linux/master/scripts/extract-vmlinux
chmod +x extract-vmlinux
./extract-vmlinux bzImage > vmlinux
```

---

## Repacking initrd (Getting Your Exploit In)

After compiling your exploit inside the container, repack it into the initrd so the QEMU guest can run it:

```bash
# Inside the Docker container — compile the exploit
gcc -o /data/exploit /data/exploit.c -static -O2

# On Mac — repack the initrd with your exploit
mkdir /tmp/initrd && cd /tmp/initrd
zcat /path/to/rootfs.cpio.gz | cpio -idmv
cp /path/to/exploit .
find . | cpio -o -H newc | gzip > /path/to/rootfs_patched.cpio.gz

# Boot with patched initrd
bash run-qemu.sh bzImage rootfs_patched.cpio.gz
```

---

## Mac Networking Gotcha

> ⚠️ `--network=host` on Docker Desktop for Mac attaches to the **Docker VM's** network — not your Mac's. `localhost:1234` inside the container points to the container itself, not QEMU on your Mac.
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

For userland CTF challenges on Apple Silicon, you'll need a different approach (e.g., a Linux VM with full KVM, or an x86_64 remote server).

---

## Troubleshooting

**`Connection refused` on `target remote host.docker.internal:1234`**
→ QEMU isn't running yet, or it crashed. Check Terminal 1 for kernel panic messages.

**Symbols not resolving after `file vmlinux`**
→ Make sure you have the unstripped `vmlinux`, not the compressed `vmlinuz` or `bzImage`.

**Kernel panic immediately on boot**
→ Try `init=/bin/sh` in APPEND to drop to shell directly.
→ Check `rootfs.cpio.gz` integrity: `file rootfs.cpio.gz`

**Build fails: `E: Unable to locate package libc6:i386`**
→ Missing `dpkg --add-architecture i386` before `apt-get update`. The provided Dockerfile handles this.

---

## Repo Structure

```
.
├── Dockerfile          # GDB + bata24/gef (linux/amd64)
├── docker-compose.yml  # alternative to alias
├── .gdbinit            # kernel defaults (intel syntax, pagination off)
└── run-qemu.sh         # QEMU launcher with CTF-friendly boot flags
```

Place these alongside your challenge files (`bzImage`, `rootfs.cpio.gz`, `vmlinux`).

---

## References

- [bata24/gef](https://github.com/bata24/gef) — GDB Enhanced Features (kernel fork)
- [QEMU GDB usage](https://qemu-project.gitlab.io/qemu/system/gdb.html)
