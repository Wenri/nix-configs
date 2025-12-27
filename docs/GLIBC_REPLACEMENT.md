# glibc Replacement Strategy for nix-on-droid

> **Last Updated:** December 27, 2024
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

### What Gets Built vs Downloaded

| Component | Source | Build Time | Size |
|-----------|--------|------------|------|
| Android glibc | **Built from source** | ~20 minutes | ~50 MB |
| Android fakechroot | **Built from source** | ~1 minute | ~200 KB |
| All other packages | **Binary cache** | Downloaded | Varies |

**Key Advantage:** No patchelf needed! The ld.so has built-in path translation and glibc redirection.

---

## Implementation Details

### File Structure

```
submodules/glibc/elf/
└── dl-android-paths.h                  # ld.so path translation (built-in to glibc)

common/overlays/
├── glibc.nix                           # Android glibc overlay (uses glibcSrc from submodule)
├── fakechroot.nix                      # Android fakechroot overlay
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
  # Base pkgs without glibc overlay (uses binary cache)
  basePkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [ /* standard overlays, NOT glibc */ ];
  };

  # Build Android-patched glibc using pre-patched source from submodule
  # The submodule contains glibc 2.40 with nixpkgs + Termux patches pre-applied
  androidGlibc = let
    glibcOverlay = import ./common/overlays/glibc.nix {
      glibcSrc = ./submodules/glibc;  # Pre-patched glibc source
    };
  in (glibcOverlay basePkgs basePkgs).glibc;

  # Build Android fakechroot with paths baked in at compile time
  androidFakechroot = import ./common/overlays/fakechroot.nix {
    inherit (basePkgs) stdenv patchelf fakechroot;
    inherit androidGlibc;
    installationDir = "/data/data/com.termux.nix/files/usr";
    src = ./submodules/fakechroot;  # Modified fakechroot source
  };
in
  nix-on-droid.lib.nixOnDroidConfiguration {
    extraSpecialArgs = {
      inherit androidGlibc androidFakechroot;
    };
    # ...
  };
```

**Key points:**
- `glibcSrc` points to the pre-patched glibc submodule (no patches applied at build time)
- `ANDROID_GLIBC_LIB` is passed via CFLAGS for runtime glibc redirection
- Fakechroot has paths baked in at compile time (no environment variables needed)

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

### ld.so Built-in Path Translation

The Android glibc's ld.so has built-in path processing in `submodules/glibc/elf/dl-android-paths.h`. The `_dl_android_process_path()` function performs two operations:

**1. Nix Store Path Translation:**
```c
/nix/store/xxx-package/lib → /data/data/com.termux.nix/files/usr/nix/store/xxx-package/lib
```

**2. Standard glibc Redirection:**
```c
// Detects paths like: xxx-glibc-2.40-66/lib (NOT xxx-glibc-android-2.40-66)
// Redirects to: ANDROID_GLIBC_LIB (compiled in via -DANDROID_GLIBC_LIB)
```

**Where it's called:**
- In `decompose_rpath()` in `dl-load.c` during RPATH/RUNPATH processing
- Each RPATH entry is processed before library search

**Memory management:**
- Returns malloc'd string (caller must free)
- Returns NULL if no processing needed
- Single function replaces previous two-function approach

**Compile-time configuration (in glibc.nix):**
```nix
env.NIX_CFLAGS_COMPILE = "-DANDROID_GLIBC_LIB=\"${nixOnDroidPrefix}${placeholder \"out\"}/lib\"";
```

### Build Process Details

The glibc source is **pre-patched** in the `submodules/glibc` git submodule. The overlay in `common/overlays/glibc.nix` performs:

1. **Use Pre-Patched Source** - glibc submodule has nixpkgs + Termux patches as git commits
2. **Skip nixpkgs Patches** - `patches = []` since already applied
3. **Build-Time Processing** - Run gen-android-ids.sh, process-fakesyscalls.sh
4. **Path Substitution** - Replace /dev/* with /proc/self/fd/*
5. **Configure Flags** - Add Android-specific configure options
6. **Compile-Time Constants** - Pass `-DANDROID_GLIBC_LIB` for runtime redirection
7. **Post-Install Fixes** - Remove broken symlinks, fix cross-output references

```nix
glibc = prev.glibc.overrideAttrs (oldAttrs: {
  pname = "glibc-android";
  src = glibcSrc;  # Pre-patched submodule
  version = "2.40-android";

  # Skip nixpkgs patches - already pre-applied in submodule
  patches = [];

  nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [ final.jq ];

  postPatch = (oldAttrs.postPatch or "") + ''
    # Remove clone3.S, run gen-android-ids.sh, process-fakesyscalls.sh
  '';

  configureFlags = oldFlags ++ [
    "--disable-nscd"
    "--disable-profile"
    "--disable-werror"
  ];

  # Pass Android glibc path for runtime redirection
  env.NIX_CFLAGS_COMPILE = "-DANDROID_GLIBC_LIB=\"...\""

  separateDebugInfo = false;  # Avoid output cycles
});
```

---

## Troubleshooting

### Common Issues

#### Library Loading Errors with Fakechroot

**Symptom:**
```bash
error while loading shared libraries: libreadline.so.8: cannot open shared object file
```

**Cause:** The dynamic linker can't find required libraries because:
1. Libraries are in separate nix packages (not in the binary's package)
2. The binary's RPATH points to `/nix/store/...` which doesn't exist on Android
3. Path translation is needed to find the real location

**Solution:** The Android glibc's ld.so has built-in path translation in `dl-android-paths.h`:
- Automatically translates `/nix/store/...` → `/data/data/.../usr/nix/store/...` during RPATH processing
- Also redirects standard glibc to Android glibc (see below)

No `LD_LIBRARY_PATH` or rtld-audit module needed!

#### glibc Redirection (Standard → Android)

**Symptom:**
```bash
$ ./some-binary
Bad system call (core dumped)
```

**Cause:** Binary from nixpkgs binary cache has RPATH pointing to standard glibc:
```
/nix/store/89n0gcl1yjp37ycca45rn50h7lms5p6f-glibc-2.40-66/lib
```
Standard glibc uses syscalls (clone3, rseq) that are blocked by Android seccomp.

**Solution:** The Android glibc's ld.so has built-in glibc redirection. During RPATH processing in `decompose_rpath()`, the `_dl_android_process_path()` function in `dl-android-paths.h`:

1. Detects paths containing `-glibc-` but NOT `-glibc-android`
2. Extracts the library suffix (e.g., `/libpthread.so.0`)
3. Redirects to the Android glibc lib directory (baked in at compile time via `-DANDROID_GLIBC_LIB`)

Example redirection:
```
/data/.../nix/store/xxx-glibc-2.40-66/lib/libc.so.6
                            ↓
/data/.../nix/store/yyy-glibc-android-2.40-66/lib/libc.so.6
```

This applies to ALL libraries from standard glibc: `libc.so.6`, `libpthread.so.0`, `libm.so.6`, `libdl.so.2`, etc.

**No environment variables needed!** The Android glibc path is compiled into ld.so at build time.

#### "Bad system call" Error

**Symptom:**
```bash
$ ./some-binary
Bad system call (core dumped)
```

**Cause:** Binary is using standard glibc that tries blocked syscalls

**Solution:** If you're running under the fakechroot login environment with Android glibc:
1. Ensure the binary is invoked through ld.so (standard for dynamically-linked binaries)
2. Verify ld.so.preload is loading libfakechroot.so
3. Check that Android glibc's path translation is working (glibc should have been built with `-DANDROID_GLIBC_LIB`)

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

#### "malloc(): corrupted top size" Error

**Symptom:**
```bash
$ nix-on-droid switch --flake .
...
Rewriting user-environment symlinks for outside-proot access
malloc(): corrupted top size
```

**Cause:** Buffer overflow in fakechroot's readlink wrapper functions. When reading symlinks to nix store paths (which can be 76+ characters like `/nix/store/pyh11hxaclcdq4qhl7zn2c1jq0b0s2mp-glibc-android-2.40-android/lib`), fakechroot was copying the full path into smaller caller buffers (e.g., 64 bytes) without checking the size, causing heap metadata corruption.

**Solution:** This was fixed in the fakechroot source (`submodules/fakechroot/src/`):
- `__readlink_chk.c` - Added buffer size check in else branch
- `__readlinkat_chk.c` - Same fix
- `readlinkat.c` - Same fix
- `libfakechroot.c` - Fixed va_start/va_end bug and replaced malloc with static storage in constructor

If you see this error, ensure you're using the latest fakechroot source from the submodule.

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
