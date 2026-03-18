# AGENTS.md — gdb-kernel-apple-silicon

## Project Overview

Docker-based GDB + bata24/gef environment for Linux kernel exploit development on Apple Silicon Macs. GDB connects to QEMU's GDB stub over TCP — no ptrace involved.

## Architecture

- **Host (Mac)**: QEMU boots x86_64 kernel via TCG, exposes GDB stub on `:1234`
- **Container (linux/amd64)**: gdb-multiarch + bata24/gef connects via `host.docker.internal:1234`
- **No ptrace**: Kernel debugging uses QEMU's GDB remote protocol, not ptrace syscalls
- **Userland debugging is NOT supported** — QEMU's ptrace emulation in Docker is broken on Apple Silicon

## Key Files

| File | Purpose |
|------|---------|
| `Dockerfile` | Full exploit dev environment — base tools + bata24/gef + kernel-specific tools |
| `run-qemu.sh` | QEMU launcher with CTF kernel boot flags (nokaslr, kpti=0, GDB stub) |
| `docker-compose.yml` | Alternative to `alias pwn` for running the container |
| `.gdbinit` | Kernel debugging defaults (intel syntax, pagination off) — appended after gef's .gdbinit |

## Conventions

- **Build target**: Always `--platform=linux/amd64` — the container runs x86_64 under QEMU
- **Image name**: `gdb-gef`
- **Alias**: `pwn` — launches the container with all required flags
- **Mount**: `-v $PWD:/data` — challenge files are at `/data` inside the container
- **Networking**: Use `host.docker.internal` to reach Mac host from container. Never use `--network=host` on Mac Docker Desktop

## Dockerfile Structure

The Dockerfile has four sections — maintain this order:

1. **Base system + build tools** — apt packages (gcc, nasm, musl-tools, checksec, etc.)
2. **bata24/gef** — installs via `install-uv.sh`. This brings ropper, rp++, one_gadget, seccomp-tools, capstone, keystone, unicorn, angr. **Do NOT duplicate these packages.**
3. **Kernel exploit dev tools** — pip packages (pwntools, ROPgadget, vmlinux-to-elf) + extract-vmlinux script + ropr (Rust)
4. **GDB config** — copies `.gdbinit` and appends to gef's generated config

## Adding New Tools

When adding tools:

1. Check if bata24/gef already installs it (see `install-uv.sh` in the gef repo)
2. Add to the correct section in the Dockerfile with a comment explaining what it does
3. Update the "What's Inside" table in README.md
4. Prefer apt packages over building from source (smaller image, faster builds)
5. Always add `--no-cache-dir` for pip installs and clean apt lists after install

## Testing Changes

```bash
# Rebuild
docker build --platform=linux/amd64 -t gdb-gef .

# Verify tools work
docker run --rm --platform=linux/amd64 gdb-gef bash -c "
  gdb --version && \
  python3 -c 'import pwn; print(pwn.version)' && \
  ROPgadget --version && \
  ropr --version && \
  vmlinux-to-elf --help 2>&1 | head -1 && \
  extract-vmlinux --help 2>&1 || true && \
  checksec --version && \
  pahole --version && \
  musl-gcc --version 2>&1 | head -1
"

# Full integration test — boot a kernel and attach
# Terminal 1: bash run-qemu.sh (with a bzImage + rootfs.cpio.gz)
# Terminal 2: pwn → gef> file /data/vmlinux → gef> target remote host.docker.internal:1234
```

## Scope Boundaries

- This repo is for **kernel debugging only** — do not add userland debugging workarounds
- Do not add `gdbserver` — it's a ptrace-based tool that doesn't work under QEMU emulation
- Do not reference Rosetta debug server — it's for Mac Mach-O binaries, not Linux ELFs
- Keep the image focused on kernel exploitation — avoid adding unrelated CTF tools (web, crypto, forensics)
