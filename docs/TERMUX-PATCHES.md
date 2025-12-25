# Termux glibc Patches for Android Compatibility

> **Last Updated:** December 2025
> **Source:** [Termux glibc-packages](https://github.com/niclasr/glibc-packages)
> **Target glibc Version:** 2.40 (from nixpkgs-unstable)

## Table of Contents

1. [Overview](#overview)
2. [Patch Categories](#patch-categories)
3. [Essential Patches (Syscall Workarounds)](#essential-patches-syscall-workarounds)
4. [Makefile Patches](#makefile-patches)
5. [Code Compatibility Patches](#code-compatibility-patches)
6. [Configuration Patches](#configuration-patches)
7. [Source Files (Non-Patches)](#source-files-non-patches)
8. [Helper Scripts](#helper-scripts)
9. [Adaptation Notes for nixpkgs](#adaptation-notes-for-nixpkgs)
10. [Updating Patches](#updating-patches)
11. [References](#references)

---

## Overview

This directory contains patches adapted from [Termux's glibc-packages](https://github.com/niclasr/glibc-packages) for Android compatibility. These patches enable glibc-based binaries to run on Android, which uses a restricted kernel with seccomp filters blocking certain syscalls.

### Patch Application Order

Patches are applied in a specific order in `common/overlays/glibc.nix`:

```nix
allPatches = [
  # 1. Essential syscall workarounds
  "disable-clone3.patch"
  "kernel-features.h.patch"
  
  # 2. Makefile modifications
  "misc-Makefile.patch"
  "misc-Versions.patch"
  "nss-Makefile.patch"
  "posix-Makefile.patch"
  "sysvipc-Makefile.patch"
  
  # 3. Code compatibility
  "clock_gettime.c.patch"
  "dl-execstack.c.patch"
  "faccessat.c.patch"
  "fchmodat.c.patch"
  "fstatat64.c.patch"
  "getXXbyYY.c.patch"
  "getXXbyYY_r.c.patch"
  "getgrgid.c.patch"
  "getgrnam.c.patch"
  "getpwnam.c.patch"
  "getpwuid.c.patch"
  "sem_open.c.patch"
  "tcsetattr.c.patch"
  "unistd.h.patch"
  
  # 4. Configuration and large patches
  "set-dirs.patch"
  "set-fakesyscalls.patch"
  "set-ld-variables.patch"
  "set-nptl-syscalls.patch"
  "set-sigrestore.patch"
  "set-static-stubs.patch"
  "syscall.S.patch"
];
```

---

## Patch Categories

### Summary Table

| Category | Patches | Purpose |
|----------|---------|---------|
| **Essential** | 4 | Disable blocked syscalls (clone3, robust_list, rseq) |
| **Makefile** | 5 | Add Android-specific source files to build |
| **Code** | 14 | Fix code for Android compatibility |
| **Configuration** | 7 | Path settings, environment variables, static stubs |

---

## Essential Patches (Syscall Workarounds)

These are the most critical patches that address Android seccomp restrictions.

### `disable-clone3.patch`

**Purpose:** Disable the clone3 syscall, forcing glibc to use the older clone() syscall

**Problem:** Android's seccomp filter blocks clone3 (syscall 435), causing thread creation to fail

**Technical Details:**
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

---

### `kernel-features.h.patch`

**Purpose:** Set Android kernel feature flags correctly

**Problem:** glibc assumes certain kernel features based on version, but Android kernels have different capabilities

**Key Changes:**
- Disables features not available in Android kernel
- Sets correct assumptions for seccomp-filtered environment
- Handles Android-specific kernel quirks

**Affected Features:**
| Feature | Standard Linux | Android |
|---------|---------------|---------|
| `clone3` | Available (5.3+) | Blocked |
| `close_range` | Available (5.9+) | May be blocked |
| `faccessat2` | Available (5.8+) | May be blocked |

---

### `set-nptl-syscalls.patch`

**Purpose:** Disable NPTL (Native POSIX Thread Library) syscalls blocked by Android

**Affected Syscalls:**

| Syscall | Purpose | Android Workaround |
|---------|---------|-------------------|
| `set_robust_list` | Register robust futex list | Disabled - futex still works |
| `rseq` | Restartable sequences | Always return "not supported" |

**Technical Details:**
```c
// set_robust_list registration disabled
// The futex mechanism still works, just without robust list feature
// Robust lists are for detecting dead lock holders - not critical

// rseq registration always fails gracefully
// This is a performance optimization that's safe to skip
```

---

### `set-fakesyscalls.patch`

**Purpose:** Provide fake implementations for blocked syscalls

**How It Works:**
1. `fakesyscall.json` defines which syscalls to fake
2. `process-fakesyscalls.sh` generates `disabled-syscall.h`
3. Syscall wrappers check header and return -ENOSYS

**Faked Syscalls:**

| Syscall | Category | Fake Return |
|---------|----------|-------------|
| `syslog` | Kernel messages | -ENOSYS |
| `epoll_pwait2` | Enhanced epoll | -ENOSYS (fallback to epoll_pwait) |
| `mq_open` | POSIX message queues | -ENOSYS |
| `mq_unlink` | POSIX message queues | -ENOSYS |
| `mq_timedsend` | POSIX message queues | -ENOSYS |
| `mq_timedreceive` | POSIX message queues | -ENOSYS |
| `mq_notify` | POSIX message queues | -ENOSYS |
| `mq_getsetattr` | POSIX message queues | -ENOSYS |

---

## Makefile Patches

These patches add Android-specific source files to the glibc build system.

### `misc-Makefile.patch`

**Purpose:** Add Android syslog implementation to misc/ build

**Adds:** `syslog.c` - Android-compatible syslog that uses Android's logging system

### `misc-Versions.patch`

**Purpose:** Export new symbols added by Android patches

**Adds:** Version definitions for Android-specific functions

### `nss-Makefile.patch`

**Purpose:** Add Android passwd/group handling to NSS build

**Adds:**
- `android_passwd_group.c` - Custom getpwuid/getgrnam for Android
- Links against Android system headers

### `posix-Makefile.patch`

**Purpose:** Add Android-specific POSIX implementations

**Adds:** Modified spawn implementations for Android

### `sysvipc-Makefile.patch`

**Purpose:** Add System V IPC emulation using Android shared memory

**Adds:**
- `shmat.c`, `shmctl.c`, `shmdt.c`, `shmget.c` - SysV shm wrappers
- `shmem-android.c` - ashmem-based implementation

---

## Code Compatibility Patches

These patches fix glibc code for Android compatibility.

### `clock_gettime.c.patch`

**Purpose:** Fix clock_gettime for Android's limited clock types

**Problem:** Android may not support all CLOCK_* types

**Changes:** Add fallbacks for unsupported clock types

---

### `dl-execstack.c.patch`

**Purpose:** Handle executable stack restrictions

**Problem:** Android has stricter executable memory restrictions

**Changes:** Disable or work around exec stack requests

---

### `faccessat.c.patch`

**Purpose:** Fix faccessat behavior on Android

**Problem:** Android's faccessat has different flag handling

**Changes:** Emulate flags not supported by kernel

---

### `fchmodat.c.patch`

**Purpose:** Fix fchmodat with AT_SYMLINK_NOFOLLOW

**Problem:** Android doesn't support AT_SYMLINK_NOFOLLOW for fchmodat

**Changes:** Implement workaround using different syscalls

---

### `fstatat64.c.patch`

**Purpose:** Fix 64-bit stat structures

**Problem:** Android kernel stat64 structure differences

**Changes:** Handle structure differences between glibc and kernel

---

### `getXXbyYY.c.patch` / `getXXbyYY_r.c.patch`

**Purpose:** Fix NSS lookup functions for Android

**Problem:** Android uses different mechanisms for user/group lookups

**Changes:** Integrate with Android passwd/group system

---

### `getgrgid.c.patch` / `getgrnam.c.patch`

**Purpose:** Fix group database lookups

**Problem:** Android has different group ID ranges and mappings

**Changes:** Use Android-specific group handling from `android_passwd_group.c`

---

### `getpwnam.c.patch` / `getpwuid.c.patch`

**Purpose:** Fix password database lookups

**Problem:** Android maps UIDs differently (app UIDs, system UIDs)

**Changes:** Use Android-specific user handling from `android_passwd_group.c`

---

### `sem_open.c.patch`

**Purpose:** Fix POSIX named semaphores

**Problem:** Android's /dev/shm is not available

**Changes:** Use alternative location or emulation

---

### `tcsetattr.c.patch`

**Purpose:** Fix terminal attribute setting

**Problem:** Android TTY handling differences

**Changes:** Handle Android-specific terminal types

---

### `unistd.h.patch`

**Purpose:** Add Android-specific declarations

**Changes:** Define missing constants and prototypes for Android

---

## Configuration Patches

### `set-dirs.patch`

**Purpose:** Replace hardcoded paths for nix-on-droid environment

**Path Replacements:**

| Original Path | Replacement |
|---------------|-------------|
| `/tmp` | `/data/data/com.termux.nix/files/tmp` |
| `/etc` | `/data/data/com.termux.nix/files/usr/etc` |
| `/var` | `/data/data/com.termux.nix/files/usr/var` |
| `/bin` | `/data/data/com.termux.nix/files/usr/bin` |
| `/sbin` | `/data/data/com.termux.nix/files/usr/bin` |

**Note:** Paths are hardcoded for nix-on-droid (unlike Termux's template approach)

---

### `set-ld-variables.patch`

**Purpose:** Configure LD_* environment variable handling

**Changes:**
- Modify LD_LIBRARY_PATH handling for Android
- Set default search paths for Android environment

---

### `set-sigrestore.patch`

**Purpose:** Fix signal handler restoration

**Problem:** Android signal handling differences

**Changes:** Use compatible signal restore mechanism

---

### `set-static-stubs.patch`

**Purpose:** Provide stubs for static linking

**Problem:** Some functions need stubs when statically linked on Android

**Changes:** Add stub implementations for unsupported features

---

### `syscall.S.patch`

**Purpose:** Assembly-level syscall wrapper modifications

**Changes:** Modify inline syscall assembly for Android compatibility

---

## Source Files (Non-Patches)

These files are copied into the glibc source tree, not applied as patches.

### System V Shared Memory Emulation

| File | Location | Purpose |
|------|----------|---------|
| `shmem-android.c` | `sysvipc/` | ashmem-based shared memory implementation |
| `shmem-android.h` | `sysvipc/` | Header for Android shared memory |
| `shmat.c` | `sysdeps/unix/sysv/linux/` | Wrapper for shmat |
| `shmctl.c` | `sysdeps/unix/sysv/linux/` | Wrapper for shmctl |
| `shmdt.c` | `sysdeps/unix/sysv/linux/` | Wrapper for shmdt |
| `shmget.c` | `sysdeps/unix/sysv/linux/` | Wrapper for shmget |

**How It Works:**
Android doesn't support System V shared memory (shmget/shmat). These files emulate it using:
1. Android's ashmem (Anonymous Shared Memory) driver
2. Memory-mapped files in `/data/data/com.termux.nix/files/usr/tmp/`

---

### Android User/Group Handling

| File | Location | Purpose |
|------|----------|---------|
| `android_passwd_group.c` | `nss/` | Custom getpwuid/getgrnam implementation |
| `android_passwd_group.h` | `nss/` | Header declarations |
| `android_system_user_ids.h` | `nss/` | Android system user/group ID mappings |
| `gen-android-ids.sh` | (script) | Generates `android_ids.h` at build time |

**Android UID Mapping:**

| Range | Type | Example |
|-------|------|---------|
| 0 | root | root |
| 1000 | system | system |
| 1001-1999 | System services | radio, bluetooth |
| 2000 | shell | shell |
| 10000-19999 | App UIDs | u0_a123 |
| 100000+ | Multi-user | u10_a123 |

---

### Syscall Wrappers

| File | Location | Purpose |
|------|----------|---------|
| `syscall.c` | `sysdeps/unix/sysv/linux/` | Generic syscall wrapper |
| `mprotect.c` | `sysdeps/unix/sysv/linux/` | Memory protection wrapper |
| `setfsuid.c` | `sysdeps/unix/sysv/linux/` | Filesystem UID wrapper |
| `setfsgid.c` | `sysdeps/unix/sysv/linux/` | Filesystem GID wrapper |
| `fake_epoll_pwait2.c` | `sysdeps/unix/sysv/linux/` | epoll_pwait2 fallback |

---

### Fake Syscall Infrastructure

| File | Purpose |
|------|---------|
| `fakesyscall.h` | Main fake syscall header |
| `fakesyscall-base.h` | Base definitions |
| `fakesyscall.json` | Syscall→fake mapping configuration |
| `process-fakesyscalls.sh` | Generates `disabled-syscall.h` |

---

### Other Files

| File | Location | Purpose |
|------|----------|---------|
| `syslog.c` | `misc/` | Android syslog using __android_log_* |
| `sdt.h` | `include/sys/` | SystemTap stub (empty) |
| `sdt-config.h` | `include/sys/` | SystemTap config stub |

---

## Helper Scripts

### `gen-android-ids.sh`

**Purpose:** Generate `android_ids.h` with Android user/group mappings

**Usage:**
```bash
./gen-android-ids.sh <prefix> <output_file> <system_ids_header>
```

**Example Output:**
```c
// android_ids.h
#define AID_ROOT 0
#define AID_SYSTEM 1000
#define AID_SHELL 2000
#define AID_APP_START 10000
// ...
```

---

### `process-fakesyscalls.sh`

**Purpose:** Generate `disabled-syscall.h` from `fakesyscall.json`

**Usage:**
```bash
./process-fakesyscalls.sh <source_dir> <patches_dir> <arch>
```

**Input (`fakesyscall.json`):**
```json
{
  "syslog": {"fake": "fake_syslog", "ret": "-ENOSYS"},
  "epoll_pwait2": {"fake": "fake_epoll_pwait2", "ret": "-ENOSYS"}
}
```

**Output (`disabled-syscall.h`):**
```c
#ifndef _DISABLED_SYSCALL_H
#define _DISABLED_SYSCALL_H

#define HAVE_FAKE_syslog 1
#define HAVE_FAKE_epoll_pwait2 1

#endif /* _DISABLED_SYSCALL_H */
```

---

## Adaptation Notes for nixpkgs

These patches were originally written for Termux's glibc 2.41 and adapted for nixpkgs' glibc 2.40.

### Key Adaptations Made

1. **Version Differences**
   - Original: glibc 2.41 (Termux)
   - Target: glibc 2.40 (nixpkgs-unstable)
   - Some patches needed context adjustments

2. **Path Handling**
   - Termux: `/data/data/com.termux/files/usr`
   - nix-on-droid: `/data/data/com.termux.nix/files/usr`
   - Paths now hardcoded in patches (no placeholders)

3. **nixpkgs Pre-patches**
   - nixpkgs applies its own patches before ours
   - `set-nptl-syscalls.patch` adjusted for nixpkgs source state

4. **Build System Differences**
   - nixpkgs uses different configure flags
   - Some patches adjusted for nixpkgs build environment

5. **Path Hardcoding**
   - `set-dirs.patch` uses hardcoded nix-on-droid paths:
     - `/data/data/com.termux.nix/files/usr` (prefix)
     - `/data/data/com.termux.nix/files` (classical prefix)
   - Unlike Termux's template approach with `@TERMUX_PREFIX@`

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
   # On Android device
   nix-on-droid switch --flake .
   # Verify basic commands work
   ```

---

## References

### Upstream Sources

- **Termux glibc-packages**: https://github.com/niclasr/glibc-packages
  - Original source of all patches
  - Maintained by Termux community
  - Check for updates when bumping glibc version

- **GNU glibc**: https://www.gnu.org/software/libc/
  - Official glibc documentation
  - Source code browser: https://sourceware.org/git/?p=glibc.git

- **nixpkgs glibc**: https://github.com/NixOS/nixpkgs/tree/master/pkgs/development/libraries/glibc
  - nixpkgs glibc package
  - See existing patches applied by nixpkgs

### Android Documentation

- **Android Bionic**: https://android.googlesource.com/platform/bionic/
  - Android's C library (not glibc)
  - Reference for Android behavior

- **seccomp in Android**: https://source.android.com/docs/security/app-sandbox
  - Android app sandbox documentation
  - Explains syscall restrictions

### Related Documentation

- [GLIBC_REPLACEMENT.md](./GLIBC_REPLACEMENT.md) - Overall glibc strategy
- [NIX-ON-DROID.md](./NIX-ON-DROID.md) - nix-on-droid configuration guide (includes fakechroot documentation)
- [../CLAUDE.md](../CLAUDE.md) - Repository overview

### Fakechroot Integration Notes

The fakechroot login script uses the Android-patched glibc with `rtld-audit` (pack-audit.so) for path rewriting. Key points:

- **Path Translation:** The audit module rewrites `/nix/store/...` paths to actual paths under `/data/data/com.termux.nix/files/usr/nix/store/...`
- **Library Discovery:** Required libraries (readline, ncursesw) are automatically discovered and added to `LD_LIBRARY_PATH`
- **Android System Tools:** The script uses `/system/bin/find` and other Android binaries for file operations since it runs locally
- **Performance:** Fakechroot provides better performance than proot by avoiding syscall emulation overhead
- **Login Shell Support:** The fakechroot source has been modified to properly handle login shells:
  - Uses original `argv[0]` (e.g., `-zsh`) for `ld.so --argv0` instead of executable path
  - Skips `argv[0]` when copying arguments if `--argv0` is used
  - Ensures shells correctly detect login status without parsing `-z` as invalid option
  - See `docs/NIX-ON-DROID.md` for detailed fakechroot modifications documentation
