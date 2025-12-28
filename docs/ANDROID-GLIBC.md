# Android glibc for nix-on-droid

> **Last Updated:** December 28, 2025
> **glibc Version:** 2.40 (from nixpkgs-unstable)
> **Target Platform:** aarch64-linux (Android/Termux)

## Table of Contents

1. [Overview](#overview)
2. [The Problem](#the-problem)
3. [Solution Architecture](#solution-architecture)
4. [Termux Patches](#termux-patches)
5. [ld.so Built-in Path Translation](#ldso-built-in-path-translation)
6. [Build System](#build-system)
7. [Troubleshooting](#troubleshooting)
8. [Updating Patches](#updating-patches)
9. [References](#references)

---

## Overview

This document describes the Android-patched glibc used in nix-on-droid. Standard glibc binaries fail on Android because the kernel uses seccomp to block certain syscalls. Our solution applies Termux community patches to glibc 2.40, creating a compatible version that works with Android's restrictions.

**Key Benefits:**
- Uses nixpkgs binary cache for most packages (no rebuilding)
- Only glibc needs to be compiled (~20 minutes)
- Build-time patching via ld.so built-in path translation
- Works with both system and home-manager packages

### What Gets Built vs Downloaded

| Component | Source | Build Time | Size |
|-----------|--------|------------|------|
| Android glibc | **Built from source** | ~20 minutes | ~50 MB |
| Android fakechroot | **Built from source** | ~1 minute | ~200 KB |
| All other packages | **Binary cache** | Downloaded | Varies |

---

## The Problem

### Android Seccomp Restrictions

Android's kernel uses seccomp (Secure Computing Mode) to filter system calls for security. When running in Termux/proot environment, many syscalls that standard Linux glibc expects are blocked:

| Syscall | Number (aarch64) | Purpose | Android Status |
|---------|------------------|---------|----------------|
| `clone3` | 435 | Modern thread/process creation | **BLOCKED** |
| `set_robust_list` | 99 | Robust futex registration | **BLOCKED** |
| `rseq` | 293 | Restartable sequences | **BLOCKED** |
| `syslog` | 116 | Kernel message buffer | **BLOCKED** |
| `mq_*` | 180-185 | POSIX message queues | **BLOCKED** |
| `epoll_pwait2` | 441 | Enhanced epoll wait | **BLOCKED** |

### Symptoms Without Patched glibc

```bash
# Example error when running standard glibc binary
$ ./hello
Bad system call (core dumped)

# Or hangs indefinitely during thread creation
$ git clone https://...
[hangs forever]
```

### Why Standard Solutions Don't Work

1. **LD_PRELOAD interposition**: Only intercepts library calls, not the dynamic linker's syscalls
2. **proot syscall emulation**: Performance overhead, doesn't cover all cases
3. **Full overlay rebuild**: Defeats binary cache, requires rebuilding 10,000+ packages

---

## Solution Architecture

Our solution uses a **two-stage approach**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    Stage 1: Build Android glibc                 │
├─────────────────────────────────────────────────────────────────┤
│  nixpkgs glibc 2.40 + Termux patches → glibc-android-2.40-xx   │
│                                                                 │
│  • Disable clone3 (use clone fallback)                         │
│  • Disable set_robust_list registration                         │
│  • Disable rseq registration                                    │
│  • Fake syscalls return -ENOSYS                                 │
│  • Android-specific passwd/group handling                       │
│  • System V shared memory emulation                             │
│  • Built-in path translation in ld.so (RPATH processing)       │
│  • Built-in glibc redirection (standard → android)             │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│        Stage 2: Runtime (ld.so built-in translation)           │
├─────────────────────────────────────────────────────────────────┤
│  The Android glibc's ld.so has built-in path processing:       │
│                                                                 │
│  1. RPATH Translation (in decompose_rpath):                    │
│     /nix/store/xxx/lib → /data/data/.../usr/nix/store/xxx/lib  │
│                                                                 │
│  2. glibc Redirection:                                          │
│     .../xxx-glibc-2.40/lib → .../xxx-glibc-android-2.40/lib    │
│                                                                 │
│  3. ld.so.preload:                                              │
│     Automatically loads libfakechroot.so for path virtualization│
│                                                                 │
│  Result: Binary cache packages work with Android glibc          │
│          without rebuild, patchelf, or rtld-audit!              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Termux Patches

Patches are adapted from [Termux's glibc-packages](https://github.com/niclasr/glibc-packages) for Android compatibility.

### Patch Categories

| Category | Count | Purpose |
|----------|-------|---------|
| **Essential** | 4 | Disable blocked syscalls (clone3, robust_list, rseq) |
| **Makefile** | 5 | Add Android-specific source files to build |
| **Code** | 14 | Fix code for Android compatibility |
| **Configuration** | 7 | Path settings, environment variables, static stubs |

### Essential Patches (Syscall Workarounds)

#### `disable-clone3.patch`

**Purpose:** Disable the clone3 syscall, forcing glibc to use the older clone() syscall

```c
// Before: glibc checks kernel version and tries clone3 first
#if __LINUX_KERNEL_VERSION >= 0x050300
  #define __ASSUME_CLONE3 1
#endif

// After: Always disable clone3
#undef __ASSUME_CLONE3
#define __ASSUME_CLONE3 0
```

**Impact:** Thread creation works via clone() fallback, ~5% slower but functional

#### `kernel-features.h.patch`

Sets Android kernel feature flags correctly. Disables features not available in Android kernel.

| Feature | Standard Linux | Android |
|---------|---------------|---------|
| `clone3` | Available (5.3+) | Blocked |
| `close_range` | Available (5.9+) | May be blocked |
| `faccessat2` | Available (5.8+) | May be blocked |

#### `set-nptl-syscalls.patch`

Disables NPTL (Native POSIX Thread Library) syscalls blocked by Android:

| Syscall | Purpose | Workaround |
|---------|---------|------------|
| `set_robust_list` | Register robust futex list | Disabled - futex still works |
| `rseq` | Restartable sequences | Always return "not supported" |

#### `set-fakesyscalls.patch`

Provides fake implementations for blocked syscalls:

| Syscall | Category | Fake Return |
|---------|----------|-------------|
| `syslog` | Kernel messages | -ENOSYS |
| `epoll_pwait2` | Enhanced epoll | -ENOSYS (fallback to epoll_pwait) |
| `mq_open` | POSIX message queues | -ENOSYS |
| `mq_unlink` | POSIX message queues | -ENOSYS |
| `mq_timedsend` | POSIX message queues | -ENOSYS |
| `mq_timedreceive` | POSIX message queues | -ENOSYS |

### Makefile Patches

| Patch | Purpose |
|-------|---------|
| `misc-Makefile.patch` | Add Android syslog implementation |
| `misc-Versions.patch` | Export Android-specific symbols |
| `nss-Makefile.patch` | Add Android passwd/group handling |
| `posix-Makefile.patch` | Add Android POSIX implementations |
| `sysvipc-Makefile.patch` | Add SysV IPC emulation using ashmem |

### Code Compatibility Patches

| Patch | Purpose |
|-------|---------|
| `clock_gettime.c.patch` | Handle limited clock types |
| `dl-execstack.c.patch` | Handle executable stack restrictions |
| `faccessat.c.patch` | Fix faccessat flag handling |
| `fchmodat.c.patch` | Fix AT_SYMLINK_NOFOLLOW handling |
| `fstatat64.c.patch` | Handle stat64 structure differences |
| `getXXbyYY.c.patch` | Fix NSS lookup functions |
| `getgrgid.c.patch` / `getgrnam.c.patch` | Fix group database lookups |
| `getpwnam.c.patch` / `getpwuid.c.patch` | Fix password database lookups |
| `sem_open.c.patch` | Fix POSIX named semaphores |
| `tcsetattr.c.patch` | Fix terminal attribute setting |
| `unistd.h.patch` | Add Android-specific declarations |

### Configuration Patches

| Patch | Purpose |
|-------|---------|
| `set-dirs.patch` | Replace hardcoded paths for nix-on-droid |
| `set-ld-variables.patch` | Configure LD_* environment variable handling |
| `set-sigrestore.patch` | Fix signal handler restoration |
| `set-static-stubs.patch` | Provide stubs for static linking |
| `syscall.S.patch` | Assembly-level syscall modifications |

### Source Files (Non-Patches)

These files are copied into the glibc source tree:

**System V Shared Memory Emulation:**
- `shmem-android.c/h` - ashmem-based shared memory implementation
- `shmat.c`, `shmctl.c`, `shmdt.c`, `shmget.c` - SysV shm wrappers

**Android User/Group Handling:**
- `android_passwd_group.c/h` - Custom getpwuid/getgrnam implementation
- `android_system_user_ids.h` - Android system user/group ID mappings
- `gen-android-ids.sh` - Generates `android_ids.h` at build time

**Android UID Mapping:**

| Range | Type | Example |
|-------|------|---------|
| 0 | root | root |
| 1000 | system | system |
| 1001-1999 | System services | radio, bluetooth |
| 2000 | shell | shell |
| 10000-19999 | App UIDs | u0_a123 |

**Fake Syscall Infrastructure:**
- `fakesyscall.h`, `fakesyscall-base.h` - Main headers
- `fakesyscall.json` - Syscall→fake mapping configuration
- `process-fakesyscalls.sh` - Generates `disabled-syscall.h`

---

## ld.so Built-in Path Translation

The Android glibc's ld.so has built-in path processing in `submodules/glibc/elf/dl-android-paths.h`. The `_dl_android_process_path()` function performs two operations:

### 1. Nix Store Path Translation

```c
/nix/store/xxx-package/lib → /data/data/com.termux.nix/files/usr/nix/store/xxx-package/lib
```

### 2. Standard glibc Redirection

```c
// Detects paths like: xxx-glibc-2.40-66/lib (NOT xxx-glibc-android-2.40-66)
// Redirects to: ANDROID_GLIBC_LIB (compiled in via -DANDROID_GLIBC_LIB)
```

**Where it's called:**
- In `decompose_rpath()` in `dl-load.c` during RPATH/RUNPATH processing
- Each RPATH entry is processed before library search

**Compile-time configuration (in glibc.nix):**
```nix
env.NIX_CFLAGS_COMPILE = "-DANDROID_GLIBC_LIB=\"${nixOnDroidPrefix}${placeholder \"out\"}/lib\"";
```

Example redirection:
```
/data/.../nix/store/xxx-glibc-2.40-66/lib/libc.so.6
                            ↓
/data/.../nix/store/yyy-glibc-android-2.40-66/lib/libc.so.6
```

This applies to ALL libraries from standard glibc: `libc.so.6`, `libpthread.so.0`, `libm.so.6`, `libdl.so.2`, etc.

**No environment variables needed!** The Android glibc path is compiled into ld.so at build time.

---

## Build System

### File Structure

```
submodules/glibc/elf/
└── dl-android-paths.h                  # ld.so path translation (built-in to glibc)

common/overlays/
├── glibc.nix                           # Android glibc overlay (uses glibcSrc from submodule)
├── fakechroot.nix                      # Android fakechroot overlay
└── patches/
    └── glibc-termux/
        ├── disable-clone3.patch        # Essential: disable clone3 syscall
        ├── kernel-features.h.patch     # Android kernel feature flags
        ├── set-nptl-syscalls.patch     # Disable set_robust_list, rseq
        ├── set-fakesyscalls.patch      # Fake syscall implementations
        ├── ... (other patches)
        ├── android_passwd_group.c      # Source files (copied, not patches)
        ├── shmem-android.c
        └── ... (other source files)
```

### Flake Integration

```nix
# In mkNixOnDroidConfiguration
mkNixOnDroidConfiguration = { hostname, system, username, ... }: let
  basePkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [ /* standard overlays, NOT glibc */ ];
  };

  # Build Android-patched glibc using pre-patched source from submodule
  androidGlibc = let
    glibcOverlay = import ./common/overlays/glibc.nix {
      glibcSrc = ./submodules/glibc;  # Pre-patched glibc source
    };
  in (glibcOverlay basePkgs basePkgs).glibc;
in
  nix-on-droid.lib.nixOnDroidConfiguration {
    extraSpecialArgs = {
      inherit androidGlibc;
    };
  };
```

### Build Process

The glibc source is **pre-patched** in the `submodules/glibc` git submodule. The overlay performs:

1. **Use Pre-Patched Source** - glibc submodule has nixpkgs + Termux patches as git commits
2. **Skip nixpkgs Patches** - `patches = []` since already applied
3. **Build-Time Processing** - Run gen-android-ids.sh, process-fakesyscalls.sh
4. **Path Substitution** - Replace /dev/* with /proc/self/fd/*
5. **Configure Flags** - Add Android-specific configure options
6. **Compile-Time Constants** - Pass `-DANDROID_GLIBC_LIB` for runtime redirection
7. **Post-Install Fixes** - Remove broken symlinks, fix cross-output references

### Building Android glibc

```bash
# Build the Android-patched glibc
nix build .#androidGlibc

# Verify the build
ls -la result/lib/
# Should contain: ld-linux-aarch64.so.1, libc.so.6, libpthread.so.0, etc.

# Check interpreter
patchelf --print-interpreter result/bin/hello
# Should show: /nix/store/...-glibc-android-2.40-xx/lib/ld-linux-aarch64.so.1
```

---

## Troubleshooting

### "Bad system call" Error

**Symptom:**
```bash
$ ./some-binary
Bad system call (core dumped)
```

**Cause:** Binary is using standard glibc that tries blocked syscalls

**Solution:** The Android glibc's ld.so has built-in glibc redirection. Ensure:
1. Binary is invoked through ld.so (standard for dynamically-linked binaries)
2. ld.so.preload is loading libfakechroot.so
3. Android glibc was built with `-DANDROID_GLIBC_LIB`

### Binary Hangs During Thread Creation

**Symptom:** Command hangs forever, especially during network operations

**Cause:** clone3 syscall blocked, glibc waiting for response

**Solution:** Ensure the binary is using Android-patched glibc with clone3 disabled

### Library Loading Errors

**Symptom:**
```bash
error while loading shared libraries: libreadline.so.8: cannot open shared object file
```

**Cause:** Dynamic linker can't find required libraries

**Solution:** The Android glibc's ld.so has built-in path translation:
- Automatically translates `/nix/store/...` → `/data/data/.../usr/nix/store/...`
- No `LD_LIBRARY_PATH` or rtld-audit needed

### "malloc(): corrupted top size" Error

**Symptom:**
```bash
$ nix-on-droid switch --flake .
...
Rewriting user-environment symlinks for outside-proot access
malloc(): corrupted top size
```

**Cause:** Buffer overflow in fakechroot's readlink wrapper functions. When reading symlinks to nix store paths (76+ characters), fakechroot was copying the full path into smaller caller buffers without checking size.

**Solution:** This was fixed in the fakechroot source (`submodules/fakechroot/src/`):
- `__readlink_chk.c` - Added buffer size check in else branch
- `__readlinkat_chk.c` - Same fix
- `readlinkat.c` - Same fix

If you see this error, ensure you're using the latest fakechroot source from the submodule.

### Doubled Paths in Wrapper Scripts

**Symptom:**
```bash
$ claude
/data/data/com.termux.nix/files/usr/data/data/com.termux.nix/files/usr/nix/store/...
# Notice the path is doubled!
```

**Cause:** The `patchPackageForAndroidGlibc` function in `flake.nix` uses `sed` to replace `/nix/store` with the Android prefix. When a package is built locally (not from binary cache), its scripts already contain the full Android-prefixed paths. The sed replacement was matching `/nix/store` within those already-prefixed paths, causing double-prefixing.

**Solution:** The patching script now skips the prefix replacement if the file already contains Android-prefixed paths:

```nix
# Skip if already prefixed (locally-built packages already have Android paths)
if ! grep -qF "${installationDir}/nix/store" "$file" 2>/dev/null; then
  sed -i "s|/nix/store|${installationDir}/nix/store|g" "$file"
fi
```

If you see this error, ensure you have the latest `flake.nix` with this check.

### Debugging Commands

```bash
# Check if binary is dynamically linked
file /path/to/binary

# Check interpreter
patchelf --print-interpreter /path/to/binary

# Check needed libraries
patchelf --print-needed /path/to/binary

# Check RPATH
patchelf --print-rpath /path/to/binary

# Trace syscalls (if strace available)
strace -f ./binary 2>&1 | grep -E "clone|robust|rseq"
```

### Build Failures

#### Patch Doesn't Apply

**Symptom:** `patch: **** malformed patch at line ...`

**Cause:** nixpkgs glibc version changed, patch context doesn't match

**Solution:**
1. Check nixpkgs glibc version: `nix eval nixpkgs#glibc.version`
2. Update patches for new version
3. Test with `--dry-run` first

#### Infinite Recursion

**Symptom:** `error: infinite recursion encountered`

**Cause:** glibc overlay creates dependency cycle

**Solution:** The overlay is NOT included in default overlays. It's only used in `mkNixOnDroidConfiguration`.

---

## Updating Patches

### When to Update

1. **New glibc version in nixpkgs** - Patches may need context adjustments
2. **New Termux patches** - Check upstream for new Android workarounds
3. **Android seccomp changes** - New syscalls may be blocked

### Update Process

1. **Check Termux upstream:**
   ```bash
   git clone https://github.com/niclasr/glibc-packages
   cd glibc-packages/gpkg/glibc
   ls *.patch
   ```

2. **Check nixpkgs glibc version:**
   ```bash
   nix eval nixpkgs#glibc.version
   ```

3. **Test patch application:**
   ```bash
   nix build .#androidGlibc 2>&1 | grep -E "patch|Hunk|FAILED"
   ```

4. **Fix failing patches:**
   - Download glibc source for target version
   - Apply patches manually to find correct context
   - Update patch files

5. **Test the build:**
   ```bash
   nix build .#androidGlibc
   # Verify: result/lib/libc.so.6 exists
   ```

6. **Test runtime:**
   ```bash
   nix-on-droid switch --flake .
   ```

### Adaptation Notes for nixpkgs

These patches were originally for Termux's glibc 2.41, adapted for nixpkgs' glibc 2.40:

| Aspect | Termux | nix-on-droid |
|--------|--------|--------------|
| Version | glibc 2.41 | glibc 2.40 |
| Prefix | `/data/data/com.termux/files/usr` | `/data/data/com.termux.nix/files/usr` |
| Paths | Templated (`@TERMUX_PREFIX@`) | Hardcoded in patches |
| Build | Termux build system | nixpkgs overlay |

---

## References

### Upstream Sources

- **Termux glibc-packages**: https://github.com/niclasr/glibc-packages
- **GNU glibc**: https://www.gnu.org/software/libc/
- **nixpkgs glibc**: https://github.com/NixOS/nixpkgs/tree/master/pkgs/development/libraries/glibc
- **nix-on-droid**: https://github.com/nix-community/nix-on-droid

### Android Documentation

- **Android Bionic**: https://android.googlesource.com/platform/bionic/
- **seccomp in Android**: https://source.android.com/docs/security/app-sandbox

### Related Documentation

- [FAKECHROOT.md](./FAKECHROOT.md) - libfakechroot documentation
- [NIX-ON-DROID.md](./NIX-ON-DROID.md) - nix-on-droid configuration guide
- [../CLAUDE.md](../CLAUDE.md) - Repository overview
