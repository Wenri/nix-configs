# Android glibc for nix-on-droid

> **Last Updated:** January 18, 2026
> **glibc Version:** 2.40 (from nixpkgs-unstable)
> **Target Platform:** aarch64-linux (Android/Termux)

## Table of Contents

1. [Overview](#overview)
2. [The Problem](#the-problem)
3. [Solution Architecture](#solution-architecture)
4. [Termux Patches](#termux-patches)
5. [patchnar: NAR Stream Patcher](#patchnar-nar-stream-patcher)
6. [Build System](#build-system)
7. [Troubleshooting](#troubleshooting)
8. [Updating Patches](#updating-patches)
9. [References](#references)

---

## Overview

This document describes the Android-patched glibc used in nix-on-droid. Standard glibc binaries fail on Android because the kernel uses seccomp to block certain syscalls. Our solution applies Termux community patches to glibc 2.40, creating a compatible version that works with Android's restrictions.

**Key Benefits:**
- Uses nixpkgs binary cache for most packages (no rebuilding)
- Only glibc and patchnar need to be compiled (~20 minutes)
- NixOS-style grafting with patchnar for recursive dependency patching
- Hash mapping ensures consistent inter-package references
- Works with both system and home-manager packages

### What Gets Built vs Downloaded

| Component | Source | Build Time | Size |
|-----------|--------|------------|------|
| Android glibc | **Built from source** | ~20 minutes | ~50 MB |
| patchnar | **Built from source** | ~2 minutes | ~1 MB |
| Android fakechroot | **Built from source** | ~1 minute | ~200 KB |
| All other packages | **Binary cache** (patched by patchnar) | Downloaded + patched | Varies |

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
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│      Stage 2: NixOS-style Grafting (patchnar + hash mapping)    │
├─────────────────────────────────────────────────────────────────┤
│  replaceAndroidDependencies function (IFD-based):               │
│                                                                 │
│  1. Discover closure with exportReferencesGraph                 │
│  2. For each package in closure:                                │
│     • Dump as NAR stream                                        │
│     • patchnar patches ELF, symlinks, scripts                   │
│     • Restore as patched package                                │
│                                                                 │
│  patchnar modifications:                                        │
│  • ELF interpreter: standard glibc → Android glibc             │
│  • ELF RPATH: add prefix + glibc substitution + hash mapping   │
│  • Symlinks: add prefix to /nix/store targets + hash mapping   │
│  • Scripts: patch shebangs with prefix + hash mapping          │
│                                                                 │
│  Hash mapping ensures all inter-package references updated      │
│  Only glibc is cutoff (special Android build, not patched)     │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Stage 3: Runtime                            │
├─────────────────────────────────────────────────────────────────┤
│  ld.so.preload loads libfakechroot.so for path virtualization   │
│  • Chroot to /data/data/.../usr                                 │
│  • Path translation for file operations                         │
│  All binaries already patched with correct glibc and paths!     │
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

## patchnar: NAR Stream Patcher

patchnar is a tool that patches NAR (Nix Archive) streams for Android compatibility. It's based on patchelf and processes NAR streams from stdin to stdout, modifying ELF binaries, symlinks, and scripts without unpacking to disk.

### How patchnar Works

```bash
nix-store --dump /nix/store/xxx-package | patchnar \
  --prefix /data/data/com.termux.nix/files/usr \
  --glibc /nix/store/yyy-glibc-android-2.40 \
  --old-glibc /nix/store/zzz-glibc-2.40 \
  --mappings /path/to/mappings.txt \
| nix-store --restore $out
```

### What patchnar Patches

| Content Type | Modification |
|--------------|--------------|
| **ELF interpreter** | Standard glibc → Android glibc |
| **ELF RPATH** | Add prefix, substitute glibc, apply hash mappings |
| **Symlinks** | Add prefix to `/nix/store/` targets, apply hash mappings |
| **Script shebangs** | Add prefix, substitute glibc, apply hash mappings |
| **All content** | Apply hash mappings for inter-package references |

### Hash Mapping

Hash mapping substitutes old store path basenames with new ones:
```
# mappings.txt format: OLD_PATH NEW_PATH
/nix/store/abc123-bash-5.2 /nix/store/xyz789-bash-5.2
```

This ensures that when package A references package B, the reference is updated to point to the patched version of B.

### Order of Operations

**Critical:** glibc substitution happens BEFORE hash mapping:

1. Replace standard glibc paths with Android glibc
2. Apply hash mappings for inter-package references
3. Add prefix to `/nix/store/` paths

This ordering is important because hash mapping would change the path and prevent glibc matching.

### Source Location

- `submodules/patchnar/src/patchnar.cc` - Main patchnar implementation
- `submodules/patchnar/src/nar.h` - NAR stream processing

---

## Build System

### File Structure

```
submodules/
├── glibc/                              # Pre-patched glibc source (from Wenri/glibc)
└── patchnar/                           # NAR stream patcher (from Wenri/patchnar)
    └── src/
        ├── patchnar.cc                 # Main patchnar implementation
        ├── nar.h                       # NAR stream processing
        ├── patchelf.cc                 # Embedded patchelf functionality
        └── elf.h                       # ELF header definitions

common/pkgs/
├── android-glibc.nix                   # Android glibc package
├── android-fakechroot.nix              # Android fakechroot package
├── patchnar.nix                        # NAR stream patcher package
└── glibc-termux/
    ├── disable-clone3.patch            # Essential: disable clone3 syscall
    ├── kernel-features.h.patch         # Android kernel feature flags
    ├── set-nptl-syscalls.patch         # Disable set_robust_list, rseq
    ├── set-fakesyscalls.patch          # Fake syscall implementations
    ├── android_passwd_group.c          # Source files (copied, not patches)
    ├── shmem-android.c
    └── ... (other patches and source files)

common/modules/android/
├── android-integration.nix             # NixOS-style grafting with patchnar
└── replace-android-dependencies.nix    # IFD-based recursive dependency patching
```

### Flake Integration

The flake builds Android packages and wires up the grafting:

```nix
# In flake.nix - Android packages
androidPkgs = import ./common/pkgs {
  inherit pkgs;
  glibcSrc = ./submodules/glibc;
  fakechrootSrc = ./submodules/fakechroot;
  patchnarSrc = ./submodules/patchnar;
};

# In android-integration.nix - grafting setup
replaceAndroidDependencies = drv:
  replaceAndroidDepsLib {
    inherit drv;
    prefix = installationDir;
    androidGlibc = glibc;
    standardGlibc = pkgs.stdenv.cc.libc;
    cutoffPackages = [ glibc ];  # Only glibc is cutoff
  };

# Applied to environment.path
build.replaceAndroidDependencies = replaceAndroidDependencies;
```

### Build Process

The build involves two main components:

**1. Android glibc** (pre-patched in `submodules/glibc`):
1. Use pre-patched source (nixpkgs + Termux patches as git commits)
2. Skip nixpkgs patches (`patches = []` since already applied)
3. Run gen-android-ids.sh, process-fakesyscalls.sh at build time
4. Replace /dev/* with /proc/self/fd/*
5. Add Android-specific configure options
6. Post-install fixes for broken symlinks

**2. patchnar** (from `submodules/patchnar`):
1. Build with autotools (autoreconfHook)
2. Links patchelf library for ELF modifications
3. Produces both `patchelf` and `patchnar` binaries

**3. NixOS-style grafting** (at package install time):
1. IFD discovers full dependency closure
2. For each package, dump → patchnar → restore
3. Hash mappings ensure consistent references

### Building Components

```bash
# Build the Android-patched glibc
nix build .#androidGlibc

# Verify glibc build
ls -la result/lib/
# Should contain: ld-linux-aarch64.so.1, libc.so.6, libpthread.so.0, etc.

# Build patchnar
nix build .#patchnar

# Verify patchnar build
result/bin/patchnar --help
# Should show usage with --prefix, --glibc, --old-glibc, --mappings options

# Build everything and apply
nix-on-droid switch --flake .
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

**Solution:** Ensure the binary was patched by patchnar:
1. Check interpreter: `patchelf --print-interpreter /path/to/binary`
   - Should point to Android glibc's ld.so
2. Check RPATH: `patchelf --print-rpath /path/to/binary`
   - Should include Android glibc path with prefix
3. Verify the package was included in `replaceAndroidDependencies` closure

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

**Solution:** Check that patchnar correctly patched the RPATH:
```bash
patchelf --print-rpath /path/to/binary
# Should show prefixed paths: /data/.../nix/store/xxx-readline-8.2/lib
```

If RPATH is missing the prefix:
1. Verify the package is in the grafting closure
2. Check for hash mapping mismatches (must be same length)
3. Rebuild with `--show-trace` to debug patchnar invocation

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

**Cause:** The `replaceAndroidDependencies` function uses `sed` to replace `/nix/store` with the Android prefix. When a package is built locally (not from binary cache), its scripts already contain the full Android-prefixed paths. The sed replacement was matching `/nix/store` within those already-prefixed paths, causing double-prefixing.

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
