# glibc Replacement Strategy for nix-on-droid

> **Last Updated:** December 2024
> **glibc Version:** 2.40 (from nixpkgs-unstable)
> **Target Platform:** aarch64-linux (Android/Termux)

## Table of Contents

1. [Overview](#overview)
2. [The Problem](#the-problem)
3. [Solution Architecture](#solution-architecture)
4. [Implementation Details](#implementation-details)
5. [Usage Guide](#usage-guide)
6. [Technical Deep Dive](#technical-deep-dive)
7. [Troubleshooting](#troubleshooting)
8. [Alternative Approaches](#alternative-approaches)
9. [References](#references)

---

## Overview

This document describes the strategy for running Nix packages on Android through nix-on-droid. The key challenge is that Android's kernel uses seccomp to block certain syscalls that standard glibc expects. Our solution builds a custom Android-patched glibc based on Termux's patches, then uses patchelf to rewrite binary headers at build time.

**Key Benefits:**
- ✅ Uses nixpkgs binary cache for most packages (no rebuilding)
- ✅ Only glibc needs to be compiled (~20 minutes)
- ✅ Build-time patching (no runtime environment hacks)
- ✅ Works with both system and home-manager packages

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

Running unpatched glibc binaries on Android causes:

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
│              Stage 2: patchelf Binary Rewriting                 │
├─────────────────────────────────────────────────────────────────┤
│  For each package from binary cache:                            │
│                                                                 │
│  Original binary:                                               │
│    Interpreter: /nix/store/xxx-glibc-2.40/lib/ld-linux-*.so.1  │
│    RPATH: /nix/store/xxx-glibc-2.40/lib:...                    │
│                                                                 │
│  After patchelf:                                                │
│    Interpreter: /nix/store/yyy-glibc-android/lib/ld-linux-*.so.1│
│    RPATH: /nix/store/yyy-glibc-android/lib:...                 │
└─────────────────────────────────────────────────────────────────┘
```

### What Gets Built vs Downloaded

| Component | Source | Build Time | Size |
|-----------|--------|------------|------|
| Android glibc | **Built from source** | ~20 minutes | ~50 MB |
| patchelf wrappers | Built (trivial) | Seconds | Copies only |
| Original packages | **Binary cache** | Downloaded | Varies |
| Final patched packages | Built (copy+patch) | Seconds per pkg | ~Same as original |

---

## Implementation Details

### File Structure

```
common/overlays/
├── glibc.nix                           # Main glibc overlay definition
├── default.nix                         # Overlay exports (doesn't include glibc by default)
└── patches/
    └── glibc-termux/
        ├── disable-clone3.patch        # Essential: disable clone3 syscall
        ├── kernel-features.h.patch     # Android kernel feature flags
        ├── set-nptl-syscalls.patch     # Disable set_robust_list, rseq
        ├── set-fakesyscalls.patch      # Fake syscall implementations
        ├── set-dirs.patch              # Path replacements for Android
        ├── set-ld-variables.patch      # LD environment variables
        ├── set-sigrestore.patch        # Signal restore handling
        ├── set-static-stubs.patch      # Static linking stubs
        ├── syscall.S.patch             # Assembly syscall wrapper
        │
        ├── misc-Makefile.patch         # Makefile modifications
        ├── misc-Versions.patch
        ├── nss-Makefile.patch
        ├── posix-Makefile.patch
        ├── sysvipc-Makefile.patch
        │
        ├── clock_gettime.c.patch       # Code compatibility patches
        ├── dl-execstack.c.patch
        ├── faccessat.c.patch
        ├── fchmodat.c.patch
        ├── fstatat64.c.patch
        ├── getXXbyYY.c.patch
        ├── getXXbyYY_r.c.patch
        ├── getgrgid.c.patch
        ├── getgrnam.c.patch
        ├── getpwnam.c.patch
        ├── getpwuid.c.patch
        ├── sem_open.c.patch
        ├── tcsetattr.c.patch
        ├── unistd.h.patch
        │
        ├── android_passwd_group.c      # Source files (copied, not patches)
        ├── android_passwd_group.h
        ├── android_system_user_ids.h
        ├── fakesyscall.h
        ├── fakesyscall-base.h
        ├── fakesyscall.json
        ├── fake_epoll_pwait2.c
        ├── gen-android-ids.sh
        ├── mprotect.c
        ├── process-fakesyscalls.sh
        ├── sdt.h
        ├── sdt-config.h
        ├── setfsgid.c
        ├── setfsuid.c
        ├── shmat.c
        ├── shmctl.c
        ├── shmdt.c
        ├── shmem-android.c
        ├── shmem-android.h
        ├── shmget.c
        ├── syscall.c
        └── syslog.c
```

### Flake Integration

The glibc overlay is integrated into `flake.nix`:

```nix
# In mkNixOnDroidConfiguration
mkNixOnDroidConfiguration = { hostname, system, username, ... }: let
  # Build Android-patched glibc using Termux patches
  androidGlibc = let
    glibcOverlay = import ./common/overlays/glibc.nix basePkgs basePkgs;
  in glibcOverlay.glibc;
  
  # Create base pkgs without glibc overlay (uses binary cache)
  basePkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [ /* standard overlays, NOT glibc */ ];
  };
  
  standardGlibc = basePkgs.stdenv.cc.libc;
  
  # Function to patch a single package to use Android glibc
  patchPackageForAndroidGlibc = pkg: basePkgs.runCommand "..." { ... } ''
    # Copy package, find ELF files, rewrite interpreter and RPATH
  '';
in
  nix-on-droid.lib.nixOnDroidConfiguration {
    extraSpecialArgs = {
      inherit androidGlibc patchPackageForAndroidGlibc;
    };
    # ...
  };
```

### The patchelf Function

```nix
patchPackageForAndroidGlibc = pkg: basePkgs.runCommand "${pkg.pname or pkg.name}-android-glibc" {
  nativeBuildInputs = [ basePkgs.patchelf basePkgs.file ];
  passthru = pkg.passthru or {};
  # Preserve meta.priority for package conflicts
} // (if pkg ? meta.priority then {meta.priority = pkg.meta.priority;} else {}) ''
  echo "=== Patching package for Android glibc ==="
  echo "Package: ${pkg.pname or pkg.name or "unknown"}"
  echo "Standard glibc: ${standardGlibc}"
  echo "Android glibc: ${androidGlibc}"
  
  # Copy the entire package (dereference symlinks)
  cp -rL ${pkg} $out
  chmod -R u+w $out
  
  # Find and patch all ELF files
  find $out -type f | while read -r file; do
    # Skip if not a dynamically-linked ELF
    if ! file "$file" 2>/dev/null | grep -q "ELF.*dynamic"; then
      continue
    fi
    
    PATCHED=0
    
    # Patch interpreter if it references standard glibc
    INTERP=$(patchelf --print-interpreter "$file" 2>/dev/null || echo "")
    if [ -n "$INTERP" ] && echo "$INTERP" | grep -q "${standardGlibc}"; then
      patchelf --set-interpreter "${androidGlibc}/lib/ld-linux-aarch64.so.1" "$file"
      PATCHED=1
    fi
    
    # Patch RPATH if it references standard glibc
    RPATH=$(patchelf --print-rpath "$file" 2>/dev/null || echo "")
    if [ -n "$RPATH" ] && echo "$RPATH" | grep -q "${standardGlibc}"; then
      NEW_RPATH=$(echo "$RPATH" | sed "s|${standardGlibc}/lib|${androidGlibc}/lib|g")
      patchelf --set-rpath "$NEW_RPATH" "$file"
      PATCHED=1
    fi
    
    [ "$PATCHED" = "1" ] && echo "  ✓ Patched: $file"
  done
''
```

---

## Usage Guide

### Current Implementation Status

**Currently, the patchelf-based patching is available but NOT automatically applied.** The nix-on-droid environment works because proot handles most syscall issues, but for better performance and compatibility, manual patching can be used.

### Building Android glibc Only

```bash
# Build the Android-patched glibc
nix build .#androidGlibc

# Verify the build
ls -la result/lib/
# Should contain: ld-linux-aarch64.so.1, libc.so.6, libpthread.so.0, etc.
```

### Using patchPackageForAndroidGlibc

In a nix-on-droid configuration module:

```nix
{ patchPackageForAndroidGlibc, pkgs, ... }: {
  # Patch specific packages that need it
  environment.packages = [
    (patchPackageForAndroidGlibc pkgs.git)
    (patchPackageForAndroidGlibc pkgs.curl)
    # Most packages work without patching under proot
    pkgs.ripgrep
    pkgs.fd
  ];
}
```

### Standalone Package Building

```bash
# Build a patched package from command line
nix build --impure --expr '
let
  flake = builtins.getFlake (toString ./.);
  patchFn = flake.lib.aarch64-linux.patchPackageForAndroidGlibc;
  pkgs = flake.inputs.nixpkgs.legacyPackages.aarch64-linux;
in
  patchFn pkgs.hello
'
```

### Verifying Patched Binaries

```bash
# Check interpreter
patchelf --print-interpreter result/bin/hello
# Should show: /nix/store/...-glibc-android-2.40-xx/lib/ld-linux-aarch64.so.1

# Check RPATH
patchelf --print-rpath result/bin/hello
# Should include: /nix/store/...-glibc-android-2.40-xx/lib

# Test execution
./result/bin/hello
# Should output: Hello, World!
```

---

## Technical Deep Dive

### Termux Patch Categories

#### 1. Syscall Disabling Patches

**`disable-clone3.patch`** - Most critical patch
```c
// Before: glibc tries clone3() first, falls back to clone()
// After: Always use clone(), never try clone3()
#undef __ASSUME_CLONE3
#define __ASSUME_CLONE3 0
```

**`set-nptl-syscalls.patch`** - Thread library patches
```c
// Disable set_robust_list registration (still works, just not registered)
// Disable rseq registration (performance feature, safe to skip)
```

#### 2. Fake Syscall Implementations

**`set-fakesyscalls.patch`** + helper files

The `fakesyscall.json` defines which syscalls to fake:
```json
{
  "syslog": {"fake": "fake_syslog", "ret": "-ENOSYS"},
  "epoll_pwait2": {"fake": "fake_epoll_pwait2", "ret": "-ENOSYS"},
  "mq_open": {"fake": "fake_mq", "ret": "-ENOSYS"}
}
```

The `process-fakesyscalls.sh` script generates `disabled-syscall.h`:
```c
#define HAVE_FAKE_syslog 1
static inline int fake_syslog(...) { return -ENOSYS; }
```

#### 3. Android-Specific Features

**passwd/group handling** - Android has different user ID mapping:
- `android_passwd_group.c` - Custom getpwuid/getgrnam implementations
- `android_system_user_ids.h` - Android system user/group IDs
- `gen-android-ids.sh` - Generates `android_ids.h` at build time

**System V shared memory emulation**:
- `shmem-android.c/h` - Emulates shmget/shmat using ashmem (Android shared memory)
- `shmat.c`, `shmctl.c`, `shmdt.c`, `shmget.c` - Wrapper implementations

#### 4. Path and Configuration Patches

**`set-dirs.patch`** - Replaces hardcoded paths:
```
/usr → /data/data/com.termux.nix/files/usr
/etc → /data/data/com.termux.nix/files/usr/etc
```

**`set-ld-variables.patch`** - LD_* environment variable handling for Android

### Build Process Details

The glibc overlay in `common/overlays/glibc.nix` performs:

1. **Patch Application** - 28 patch files in specific order
2. **File Installation** - Copy source files to appropriate directories
3. **Code Generation** - Run helper scripts to generate headers
4. **Path Substitution** - Replace /dev/* with /proc/self/fd/*
5. **Configure Flags** - Add Android-specific configure options
6. **Post-Install Fixes** - Remove broken symlinks, fix cross-output references

```nix
glibc = prev.glibc.overrideAttrs (oldAttrs: {
  pname = "glibc-android";
  
  patches = (oldAttrs.patches or []) ++ (map (p: termuxPatches + "/${p}") allPatches);
  
  nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ final.jq ];
  
  postPatch = (oldAttrs.postPatch or "") + ''
    # Remove clone3.S, install source files, generate headers, etc.
  '';
  
  configureFlags = oldFlags ++ [
    "--disable-nscd"
    "--disable-profile"
    "--disable-werror"
  ];
  
  separateDebugInfo = false;  # Avoid output cycles
});
```

---

## Troubleshooting

### Common Issues

#### "Bad system call" Error

**Symptom:**
```bash
$ ./some-binary
Bad system call (core dumped)
```

**Cause:** Binary is using standard glibc that tries blocked syscalls

**Solution:**
1. Use `patchPackageForAndroidGlibc` to patch the package
2. Or run under proot which handles syscall emulation

#### Binary Hangs During Thread Creation

**Symptom:** Command hangs forever, especially during network operations

**Cause:** clone3 syscall blocked, glibc waiting for response

**Solution:** Ensure the binary is using Android-patched glibc with clone3 disabled

#### "cannot execute binary file" Error

**Symptom:**
```bash
$ ./binary
bash: ./binary: cannot execute binary file: Exec format error
```

**Cause:** Wrong architecture (x86_64 binary on aarch64)

**Solution:** Ensure you're building for `aarch64-linux`

### Debugging Commands

```bash
# Check if binary is dynamically linked
file /path/to/binary
# Output should include "dynamically linked"

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

**Solution:** The overlay is intentionally NOT included in default overlays. It's only used in `mkNixOnDroidConfiguration`.

---

## Alternative Approaches

### Approaches Considered But Not Used

| Approach | Pros | Cons | Why Not Used |
|----------|------|------|--------------|
| **Full overlay** | Complete solution | Rebuilds 10,000+ packages | Defeats binary cache |
| **replaceDependencies** | Nix native | Experimental, complex | Unreliable, incomplete |
| **LD_PRELOAD** | No rebuild needed | Can't fix interpreter | Doesn't intercept ld.so |
| **Termux glibc-runner** | No rebuild needed | External dependency | Adds complexity |
| **proot syscall emulation** | Works for most cases | Performance overhead | Already used, not sufficient for all cases |

### Why patchelf + Custom glibc?

1. **Binary cache preserved** - Only glibc built from source
2. **Build-time patching** - No runtime environment hacks
3. **Selective patching** - Only patch packages that need it
4. **Reproducible** - Nix derivations ensure consistent results

---

## References

### Upstream Sources

- **Termux glibc-packages**: https://github.com/niclasr/glibc-packages
  - Original patches for Android compatibility
  - Maintained by Termux community

- **GNU glibc**: https://www.gnu.org/software/libc/
  - Official glibc source and documentation

- **nixpkgs glibc**: https://github.com/NixOS/nixpkgs/tree/master/pkgs/development/libraries/glibc
  - nixpkgs glibc package and patches

- **nix-on-droid**: https://github.com/nix-community/nix-on-droid
  - Nix package manager for Android/Termux

### Related Documentation

- [NIX-ON-DROID.md](./NIX-ON-DROID.md) - Quick start guide for nix-on-droid
- [TERMUX-PATCHES.md](./TERMUX-PATCHES.md) - Detailed patch documentation
- [CLAUDE.md](../CLAUDE.md) - Repository overview and conventions

### Android Seccomp Documentation

- Android Bionic source: https://android.googlesource.com/platform/bionic/
- seccomp filter: https://android.googlesource.com/platform/bionic/+/refs/heads/master/libc/seccomp/
