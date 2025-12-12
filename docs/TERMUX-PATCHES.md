# Termux glibc Patches

This directory contains patches adapted from [Termux's glibc-packages](https://github.com/niclasr/glibc-packages) for Android compatibility.

## Patch Overview

### Essential Patches (Android Seccomp Workarounds)

| Patch | Purpose |
|-------|---------|
| `disable-clone3.patch` | Disable clone3 syscall, use clone() fallback |
| `kernel-features.h.patch` | Android kernel feature detection |
| `set-nptl-syscalls.patch` | Disable set_robust_list and rseq registration |
| `set-fakesyscalls.patch` | Generate fake implementations for blocked syscalls |

### Directory and Path Patches

| Patch | Purpose |
|-------|---------|
| `set-dirs.patch` | Set PREFIX paths for nix store |
| `set-ldso.patch` | Set dynamic linker path |
| `set-version.patch` | Set version string |

### Locale and Character Set Patches

| Patch | Purpose |
|-------|---------|
| `locale-dir.patch` | Locale data directory |
| `locale-relative.patch` | Relative locale paths |

### Compatibility Patches

| Patch | Purpose |
|-------|---------|
| `disable-kernel-memory-protection-for-setuid.patch` | Android memory protection |
| `fix-RLIMIT_NLIMITS.patch` | Resource limit compatibility |
| `getlogin_r.patch` | Login name function |
| `headers-1-fix-PATH_MAX.patch` | Path length constant |
| `headers-2-stub-arm-ucontext.patch` | ARM context stubs |
| `ld-so-ndk-workaround.patch` | NDK compatibility |
| `proc-stat.patch` | /proc/stat parsing |
| `sys-stat.patch` | stat() compatibility |
| `sys-statfs.patch` | statfs() compatibility |
| `sys-statvfs.patch` | statvfs() compatibility |

### Build System Patches

| Patch | Purpose |
|-------|---------|
| `config.patch` | Configure script |
| `config-2.patch` | Additional configure |
| `getprotoent.patch` | Protocol entry functions |
| `libc-err.patch` | Error handling |
| `libc-misc.patch` | Miscellaneous fixes |
| `string-misc.patch` | String functions |
| `sysdep-misc.patch` | System-dependent code |

## Helper Files

- `fakesyscall.json` - Mapping of syscalls to fake implementations
- `process-fakesyscalls.sh` - Generates `disabled-syscall.h` from JSON

## Adaptation Notes

These patches were adapted from Termux's glibc 2.40 packages with modifications:

1. **Path changes**: Termux uses `/data/data/com.termux/files/usr`, we use nix store paths
2. **Source differences**: nixpkgs applies its own patches before ours
3. **Build system**: nixpkgs uses different configure flags

### Key Adaptations Made

1. `set-dirs.patch` - Uses `@PREFIX@` placeholder substituted at build time
2. `set-nptl-syscalls.patch` - Adapted for nixpkgs' already-modified source
3. `kernel-features.h.patch` - Accounts for nixpkgs patches

## Upstream Sources

- Termux glibc-packages: https://github.com/niclasr/glibc-packages
- GNU glibc: https://www.gnu.org/software/libc/
- nixpkgs glibc: https://github.com/NixOS/nixpkgs/tree/master/pkgs/development/libraries/glibc

## Updating Patches

When updating to a new glibc version:

1. Check Termux's patches for the target version
2. Apply patches in order, fixing conflicts
3. Test compilation: `nix build .#androidGlibc`
4. Test runtime: Verify patched binaries run without "Bad system call"

```bash
# Test patch application
nix-shell -p gnupatch --run "
  patch -p1 --dry-run < patches/glibc-termux/disable-clone3.patch
"
```
