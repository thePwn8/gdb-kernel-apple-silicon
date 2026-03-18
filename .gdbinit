# Kernel debugging defaults
# Appended to /root/.gdbinit after bata24/gef is sourced

set architecture i386:x86-64
set disassembly-flavor intel
set pagination off

# Pretty-print kernel structs
set print pretty on
set print object on

# Silence "detached from process" noise
set confirm off

# When debugging with KASLR: after connecting, run `kbase` (bata24/gef) to get slide
# Then symbols resolve automatically via vmlinux + KASLR offset

# Common kernel breakpoints (uncomment as needed):
# b panic
# b __do_kernel_fault
# b do_general_protection
