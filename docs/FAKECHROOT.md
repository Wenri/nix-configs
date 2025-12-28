# libfakechroot for nix-on-droid

> **Last Updated:** December 28, 2025
> **Source:** `submodules/fakechroot/` (forked from dex4er/fakechroot)
> **Target Platform:** aarch64-linux (Android/Termux)

## Table of Contents

1. [Overview](#overview)
2. [How It Works](#how-it-works)
3. [Integration with Android glibc](#integration-with-android-glibc)
4. [Modifications for nix-on-droid](#modifications-for-nix-on-droid)
5. [Build Configuration](#build-configuration)
6. [Troubleshooting](#troubleshooting)
7. [References](#references)

---

## Overview

libfakechroot is an LD_PRELOAD library that intercepts filesystem-related system calls and translates paths. In nix-on-droid, it provides path virtualization for the Nix environment, allowing binaries to see paths like `/nix/store/...` while the actual files are at `/data/data/com.termux.nix/files/usr/nix/store/...`.

### Key Properties

| Property | Value |
|----------|-------|
| **Type** | LD_PRELOAD shared library |
| **Maintained in** | `submodules/fakechroot/` (separate git repo) |
| **Loaded via** | `ld.so.preload` (automatic) |
| **Purpose** | Path translation for `/nix/store` and chroot virtualization |
| **Built with** | Android glibc for compatibility |

### Why Separate from glibc?

libfakechroot is maintained separately because:

1. **Different update cycles** - Fakechroot changes more frequently than glibc
2. **Easier debugging** - Can be rebuilt quickly without rebuilding glibc
3. **Clear separation** - glibc handles syscall compatibility, fakechroot handles path virtualization
4. **Upstream tracking** - Easier to merge upstream fakechroot changes

---

## How It Works

### Library Preloading

The Android glibc's `ld.so` automatically loads libfakechroot via `/etc/ld.so.preload`:

```
# /etc/ld.so.preload
/data/data/com.termux.nix/files/usr/nix/store/xxx-fakechroot/lib/fakechroot/libfakechroot.so
```

This is configured by nix-on-droid during `nix-on-droid switch`.

### Function Interception

libfakechroot wraps filesystem functions to translate paths:

```c
// Example: open() interception
wrapper(open, int, (const char * path, int flags, ...)) {
    char fakechroot_abspath[FAKECHROOT_PATH_MAX];
    char fakechroot_buf[FAKECHROOT_PATH_MAX];

    // Translate path: /nix/store/... → /data/data/.../nix/store/...
    expand_chroot_path(path);

    // Call the real open() with translated path
    return nextcall(open)(path, flags, mode);
}
```

### Intercepted Functions

Key function categories:

| Category | Functions |
|----------|-----------|
| **File I/O** | open, openat, fopen, freopen, creat |
| **Directory** | opendir, readdir, mkdir, rmdir, chdir |
| **Symlinks** | readlink, readlinkat, symlink |
| **Stats** | stat, lstat, fstat, access, faccessat |
| **Exec** | execve, execv, execvp, posix_spawn |

---

## Integration with Android glibc

### Path Translation Layers

nix-on-droid uses two complementary path translation mechanisms:

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Binary                        │
│                          │                                   │
│                          ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              libfakechroot.so (LD_PRELOAD)              ││
│  │  • Intercepts filesystem calls (open, stat, exec, etc.) ││
│  │  • Translates /nix/store → /data/.../nix/store          ││
│  │  • Handles chroot virtualization                         ││
│  └─────────────────────────────────────────────────────────┘│
│                          │                                   │
│                          ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │           Android glibc ld.so (built-in)                ││
│  │  • RPATH translation during library loading             ││
│  │  • Standard glibc → Android glibc redirection           ││
│  │  • Loads libfakechroot via ld.so.preload                ││
│  └─────────────────────────────────────────────────────────┘│
│                          │                                   │
│                          ▼                                   │
│                    Linux Kernel                              │
└─────────────────────────────────────────────────────────────┘
```

### ld.so.preload

The Android glibc's ld.so reads `/etc/ld.so.preload` and loads listed libraries before the application starts. This ensures libfakechroot is active for all filesystem operations.

### Compile-Time Configuration

libfakechroot is built with paths baked in at compile time:

```nix
# common/overlays/fakechroot.nix
NIX_CFLAGS_COMPILE = builtins.concatStringsSep " " [
  "-DANDROID_ELFLOADER=\"${androidLdso}\""
  "-DANDROID_BASE=\"${installationDir}\""
  "-DANDROID_EXCLUDE_PATH=\"${excludePath}\""
];
```

---

## Modifications for nix-on-droid

The fakechroot source in `submodules/fakechroot/` has been modified from upstream:

### 1. Login Shell argv[0] Handling

**Problem:** When using `ld.so --argv0` to set the program name (e.g., `-zsh` for login shells), fakechroot was:
1. Using the executable path instead of original `argv[0]` for `--argv0`
2. Copying `argv[0]` as a regular argument, causing shells to see `-zsh` as an option

**Fix:** Modified `execve.c` and `posix_spawn.c` to:
1. Use original `argv[0]` for `ld.so --argv0`
2. Skip `argv[0]` when copying arguments if `--argv0` is used

**Files modified:**
- `submodules/fakechroot/src/execve.c`
- `submodules/fakechroot/src/posix_spawn.c`

This ensures login shells correctly detect their status without parsing `-z` as an invalid option.

### 2. Hashbang Script Path Fix

**Problem:** When executing hashbang scripts (e.g., `#!/bin/bash`), fakechroot was passing `argv[0]` (the command name like "claude") instead of the actual script path to the interpreter.

**Symptom:**
```bash
$ FAKECHROOT_DEBUG=1 claude --version
# Shows infinite loop: bash is invoked, searches PATH, finds claude, loops
```

**Cause:** The hashbang handling code was doing:
```c
newargv[n++] = argv0;  // WRONG: passes "claude" instead of script path
```

**Fix:** Pass the expanded script path instead:
```c
newargv[n++] = filename;  // Correct: passes "/path/to/.claude-wrapped"
```

**Files modified:**
- `submodules/fakechroot/src/execve.c`
- `submodules/fakechroot/src/posix_spawn.c`

### 3. Improved argv[0] for ps/top Display

**Problem:** When fakechroot invoked `ld.so` to run binaries, it was setting `argv[0]` to `ANDROID_ELFLOADER` (the ld.so path). This caused all processes to show as "ld-linux-aarch64.so.1" in `ps` and `top` output.

**Before:**
```bash
$ ps
  PID TTY          TIME CMD
12345 ?        00:00:00 ld-linux-aarch64.so.1
```

**Fix:** Use the original command name as `ld.so`'s `argv[0]`:

```c
// Before (uninformative):
newargv[0] = ANDROID_ELFLOADER;  // "/path/to/ld-linux-aarch64.so.1"

// After (informative):
newargv[0] = argv0;              // "sleep", "claude", etc.
```

**After:**
```bash
$ ps
  PID TTY          TIME CMD
12345 ?        00:00:00 sleep
```

**argv layout:**
```
[argv0, --argv0, argv0, program/interpreter, args...]
 └─ for ps   └─ for $0
```

**Files modified:**
- `submodules/fakechroot/src/execve.c` (both hashbang and non-hashbang sections)
- `submodules/fakechroot/src/posix_spawn.c` (both hashbang and non-hashbang sections)

### 4. Readlink Buffer Overflow Fix

**Problem:** Buffer overflow in readlink wrapper functions. When reading symlinks to nix store paths (76+ characters like `/nix/store/pyh11hxaclcdq4qhl7zn2c1jq0b0s2mp-glibc-android-2.40-android/lib`), fakechroot was copying the full path into smaller caller buffers (e.g., 64 bytes) without checking size, causing heap metadata corruption.

**Symptom:**
```bash
$ nix-on-droid switch --flake .
Rewriting user-environment symlinks for outside-proot access
malloc(): corrupted top size
```

**Fix:** Added buffer size check in the else branch of readlink wrappers:

```c
// Before (buggy):
else {
    strncpy(buf, tmp, linksize);  // No size check!
}

// After (fixed):
else {
    if (linksize > bufsiz) {
        linksize = bufsiz;
    }
    strncpy(buf, tmp, linksize);
}
```

**Files modified:**
- `submodules/fakechroot/src/__readlink_chk.c`
- `submodules/fakechroot/src/__readlinkat_chk.c`
- `submodules/fakechroot/src/readlinkat.c`

### 5. va_start/va_end Fix

**Problem:** In `libfakechroot.c`, the `fakechroot_debug()` function called `va_start()` then returned early without `va_end()`, causing undefined behavior.

**Fix:**
```c
// Before (buggy):
LOCAL int fakechroot_debug (const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    if (!getenv("FAKECHROOT_DEBUG"))
        return 0;  // va_end never called!
    // ...
}

// After (fixed):
LOCAL int fakechroot_debug (const char *fmt, ...) {
    va_list ap;
    // Check BEFORE va_start
    if (!getenv("FAKECHROOT_DEBUG"))
        return 0;
    va_start(ap, fmt);
    // ...
    va_end(ap);
    return ret;
}
```

**File modified:**
- `submodules/fakechroot/src/libfakechroot.c`

### 6. Static Storage for Exclude List

**Problem:** Using `malloc()` in library constructor on Android was unreliable.

**Fix:** Changed from dynamic allocation to static storage:

```c
// Before:
static char **exclude_list = NULL;
exclude_list = malloc(sizeof(char*) * MAX_EXCLUDES);

// After:
static char *exclude_list[MAX_EXCLUDES];
static char exclude_storage[8192];
```

**File modified:**
- `submodules/fakechroot/src/libfakechroot.c`

---

## Build Configuration

### Nix Overlay

```nix
# common/overlays/fakechroot.nix
{ stdenv, patchelf, fakechroot, androidGlibc, installationDir, excludePath, src }:
let
  androidGlibcAbs = "${installationDir}${androidGlibc}/lib";
  androidLdso = "${androidGlibcAbs}/ld-linux-aarch64.so.1";
in
fakechroot.overrideAttrs (oldAttrs: {
  pname = "fakechroot-android";
  version = "unstable-local";
  inherit src;
  patches = [];

  NIX_CFLAGS_COMPILE = builtins.concatStringsSep " " [
    (oldAttrs.NIX_CFLAGS_COMPILE or "")
    "-DANDROID_ELFLOADER=\"${androidLdso}\""
    "-DANDROID_BASE=\"${installationDir}\""
    "-DANDROID_EXCLUDE_PATH=\"${excludePath}\""
  ];

  postFixup = (oldAttrs.postFixup or "") + ''
    for bin in $out/bin/fakechroot $out/bin/ldd.fakechroot; do
      if [ -f "$bin" ]; then
        patchelf --set-interpreter "${androidLdso}" --set-rpath "${androidGlibcAbs}" "$bin"
      fi
    done
  '';
})
```

### Compile-Time Constants

| Constant | Purpose |
|----------|---------|
| `ANDROID_ELFLOADER` | Path to Android glibc's ld.so |
| `ANDROID_BASE` | Installation prefix (`/data/data/com.termux.nix/files/usr`) |
| `ANDROID_EXCLUDE_PATH` | Paths to exclude from translation (e.g., `/proc:/sys:/dev`) |

### Building

```bash
# Build Android fakechroot
nix build .#androidFakechroot

# Verify
ls -la result/lib/fakechroot/
# Should contain: libfakechroot.so
```

---

## Troubleshooting

### libfakechroot Not Loading

**Symptom:** Path translation not working, binaries fail to find libraries

**Check:**
```bash
# Verify ld.so.preload exists
cat /etc/ld.so.preload

# Check library exists
ls -la $(cat /etc/ld.so.preload)

# Test with LD_DEBUG
LD_DEBUG=libs /bin/ls 2>&1 | head -20
```

### Path Translation Not Working

**Symptom:** `open("/nix/store/...")` fails with ENOENT

**Check:**
```bash
# Verify FAKECHROOT_BASE is set (if not using compile-time)
echo $FAKECHROOT_BASE

# Check exclude paths
echo $FAKECHROOT_EXCLUDE_PATH
```

### malloc() Corrupted Top Size

**Symptom:**
```bash
malloc(): corrupted top size
```

**Cause:** Buffer overflow in readlink wrappers (see modifications above)

**Solution:** Ensure you're using the latest fakechroot from the submodule

### Login Shell Issues

**Symptom:** Shell fails with "invalid option -z" or doesn't act as login shell

**Cause:** argv[0] not properly set for login shells

**Solution:** Ensure you're using the modified fakechroot with argv[0] fix

---

## References

### Source Repositories

- **Upstream fakechroot**: https://github.com/dex4er/fakechroot
- **Our fork**: `submodules/fakechroot/` (tracking Wenri/fakechroot)

### Related Documentation

- [ANDROID-GLIBC.md](./ANDROID-GLIBC.md) - Android glibc documentation
- [NIX-ON-DROID.md](./NIX-ON-DROID.md) - nix-on-droid configuration guide
- [../CLAUDE.md](../CLAUDE.md) - Repository overview

### Technical References

- **LD_PRELOAD**: https://man7.org/linux/man-pages/man8/ld.so.8.html
- **dlsym RTLD_NEXT**: Used to call original functions after interception
