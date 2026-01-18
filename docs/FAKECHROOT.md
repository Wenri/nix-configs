# libfakechroot for nix-on-droid

> **Last Updated:** January 17, 2026
> **Source:** `submodules/fakechroot/` (forked from dex4er/fakechroot)
> **Target Platform:** aarch64-linux (Android/Termux)

## Table of Contents

1. [Overview](#overview)
2. [How It Works](#how-it-works)
3. [Integration with Android glibc](#integration-with-android-glibc)
4. [Modifications for nix-on-droid](#modifications-for-nix-on-droid)
5. [Android Seccomp Bypass](#android-seccomp-bypass)
6. [Build Configuration](#build-configuration)
7. [Troubleshooting](#troubleshooting)
8. [References](#references)

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

libfakechroot is built with paths baked in at compile time. The Nix package passes Android configuration as environment variables to `./configure`, which uses `AC_ARG_VAR` and `AC_DEFINE_UNQUOTED` to write them to `config.h`:

```nix
# common/pkgs/android-fakechroot.nix
# Pass Android paths to configure via AC_ARG_VAR environment variables
# These get written to config.h via AC_DEFINE_UNQUOTED
ANDROID_ELFLOADER = androidLdso;
ANDROID_BASE = installationDir;
ANDROID_EXCLUDE_PATH = excludePath;
```

The configure script defines these in `config.h`:
```c
/* In generated config.h */
#define ANDROID_ELFLOADER "/data/data/com.termux.nix/files/usr/nix/store/.../ld-linux-aarch64.so.1"
#define ANDROID_BASE "/data/data/com.termux.nix/files/usr"
#define ANDROID_EXCLUDE_PATH "/3rdmodem:/acct:/apex:..."
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

### 2. Kernel-Style Shebang Parsing

**Problem:** Original fakechroot split shebang arguments on every whitespace, which differs from Linux kernel behavior. The kernel only passes ONE optional argument after the interpreter.

**Linux kernel behavior:**
```bash
#!/usr/bin/env python3        # interpreter="/usr/bin/env", arg="python3"
#!/usr/bin/env -S python3 -u  # interpreter="/usr/bin/env", arg="-S python3 -u" (one string!)
```

**Fix:** Aligned shebang parsing with kernel behavior:
- Parse interpreter path (first token)
- Parse optional single argument (everything after whitespace until newline)

**Constants defined in `execve.h`:**
```c
#define EXEC_PREFIX_LEN 4     /* [argv0, --argv0, argv0, program] */
#define MAX_SHEBANG_ARGS 1    /* Kernel only passes 1 arg */
```

**Files modified:**
- `submodules/fakechroot/src/execve.c`
- `submodules/fakechroot/src/execve.h`
- `submodules/fakechroot/src/posix_spawn.c`

### 3. Hashbang Script Path Fix

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

### 4. Improved argv[0] for ps/top Display

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

**argv layout (EXEC_PREFIX_LEN = 4):**
```
[argv0, --argv0, argv0, program, args...]
   │       │       │       │
   │       │       │       └─ ELF: expanded binary path
   │       │       │          Script: expanded interpreter path
   │       │       └─ program's argv[0] (for $0, $^X)
   │       └─ ld.so option
   └─ ld.so's argv[0] (for ps/top display)
```

For scripts with shebang args (e.g., `#!/usr/bin/env python3`):
```
[argv0, --argv0, argv0, interpreter, shebang_arg, script, user_args...]
```

**Files modified:**
- `submodules/fakechroot/src/execve.c` (both hashbang and non-hashbang sections)
- `submodules/fakechroot/src/posix_spawn.c` (both hashbang and non-hashbang sections)

### 5. Readlink Buffer Overflow Fix

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

### 6. va_start/va_end Fix

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

### 7. Static Storage for Exclude List

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

### 8. SIGSYS Handler for Android Seccomp Bypass

**Problem:** Android's seccomp filter blocks certain syscalls (like `faccessat2`, syscall 439) that newer glibc and Go use. When blocked, the kernel sends SIGSYS which crashes the process.

**Symptom:**
```bash
$ glab --version
SIGSYS: bad system call
PC=0x16af0 m=0 sigcode=1
```

**Solution:** Install a SIGSYS handler that intercepts blocked syscalls and returns ENOSYS, allowing runtimes to fall back to alternative syscalls.

```c
// In libfakechroot.c
void fakechroot_sigsys_handler(int sig, siginfo_t *info, void *ucontext)
{
    if (info->si_code == SYS_SECCOMP && info->si_syscall == SYS_faccessat2) {
        ucontext_t *ctx = (ucontext_t *)ucontext;
        ctx->uc_mcontext.regs[0] = -ENOSYS;  // Return ENOSYS
        return;
    }
    // Chain to saved handler for other signals
}
```

**Files modified:**
- `submodules/fakechroot/src/libfakechroot.c`

### 9. sigaction Wrapper for Go Compatibility

**Problem:** Go's runtime installs its own SIGSYS handler during startup, which overrides our handler. Go's handler panics on SIGSYS from seccomp.

**Solution:** Wrap `sigaction()` to intercept Go's attempt to install a SIGSYS handler:

1. When code calls `sigaction(SIGSYS, ...)`, save the handler but don't install it
2. Keep our SIGSYS handler installed
3. Chain to the saved handler for signals we don't handle

```c
// In sigaction.c
wrapper(sigaction, int, (int signum, const struct sigaction *act, struct sigaction *oldact))
{
    if (signum != SIGSYS)
        return nextcall(sigaction)(signum, act, oldact);

    // Save Go's handler for chaining
    memcpy(&saved_sigsys_handler, act, sizeof(struct sigaction));
    have_saved_sigsys_handler = 1;

    // Don't actually install their handler - keep ours
    return 0;
}
```

**Files added:**
- `submodules/fakechroot/src/sigaction.c`

**Files modified:**
- `submodules/fakechroot/src/Makefile.am`
- `submodules/fakechroot/src/libfakechroot.c`

**Result:** Go binaries like `glab` now work on Android:
```bash
$ glab --version
glab 1.80.4 (f4b518e)
```

### 10. Direct Execution for Script Interpreters

**Problem:** When executing scripts with shebang lines (e.g., `#!/usr/bin/env python3`), fakechroot always wrapped the interpreter with `ld.so --argv0`. This was unnecessary overhead for interpreters that were already patched to use Android glibc or the nix-ld shim.

**Solution:** Check the script interpreter's PT_INTERP section to determine if ld.so wrapping is needed:

1. Parse the shebang line and expand the interpreter path
2. Open the interpreter ELF and read its PT_INTERP
3. If PT_INTERP points to a "direct-exec" linker, execute without wrapping
4. Otherwise, use the standard `ld.so --argv0` wrapper

**Direct-exec linkers recognized:**
- `ANDROID_ELFLOADER` (Android glibc's ld.so)
- nix-ld shim (`/data/data/com.termux.nix/files/usr/lib/ld-linux-aarch64.so.1`)
- Android Bionic (`/system/bin/linker64`, `/system/bin/linker`)

**Execution types:**
```c
typedef enum {
    /* Direct execution (no ld.so wrapper needed) */
    EXEC_TYPE_DIRECT_ELF,       /* ELF with direct-exec PT_INTERP */
    EXEC_TYPE_DIRECT_LDSO,      /* Executing ld.so itself */
    EXEC_TYPE_DIRECT_SCRIPT,    /* Script with direct-exec interpreter */

    /* Elfloader wrapped execution (needs ld.so wrapper) */
    EXEC_TYPE_ELFLOADER_ELF,    /* Regular ELF binary */
    EXEC_TYPE_ELFLOADER_SCRIPT, /* Script with regular interpreter */
} exec_type_t;
```

**Argv layout comparison:**

*Direct script execution* (interpreter already patched):
```
[displayArgv0, shebang_arg?, script_path, user_args...]
```
Note: `displayArgv0` is the original shebang interpreter (e.g., `/usr/bin/perl`),
matching kernel behavior. The actual executed binary is `ctx->interpPath`
(the expanded path like `/nix/store/.../bin/perl`).

*Wrapped script execution* (needs ld.so):
```
[displayArgv0, --argv0, displayArgv0, interpPath, shebang_arg?, script_path, user_args...]
```

**Buffer reuse optimization:**

The implementation reuses `exec_ctx_t` buffers to minimize stack usage (~12KB+ saved):

| Buffer | Usage during exec_prepare | Usage during script parsing |
|--------|---------------------------|----------------------------|
| `ctx.interpPath` | Temp for path expansion | Expanded interpreter path |
| `ctx.hashbang` | Temp for path expansion, then file header | Shebang line / PT_INTERP |

**Files modified:**
- `submodules/fakechroot/src/execve.c`
- `submodules/fakechroot/src/execve.h`
- `submodules/fakechroot/src/posix_spawn.c`

**Result:** Scripts with patched interpreters execute faster without unnecessary ld.so wrapper overhead.

### 11. syscall() Wrapper for Direct Syscall Interception

**Problem:** Some libraries (notably libuv, used by Node.js) bypass glibc wrappers and call `syscall()` directly for certain operations. For example, libuv uses `syscall(__NR_statx, ...)` instead of the glibc `statx()` function. This bypasses libfakechroot's LD_PRELOAD interception, causing path translation to fail.

**Symptom:**
```bash
$ strace -e statx node -e 'require("fs").statSync("/nix/store")'
statx(AT_FDCWD, "/nix/store", ...) = -1 ENOENT (No such file or directory)
# Path NOT translated - should be /data/data/.../nix/store
```

**Solution:** Add a `syscall()` wrapper that intercepts direct syscalls and translates paths for path-related syscall numbers:

```c
wrapper(syscall, long, (long number, ...))
{
    va_list ap;
    va_start(ap, number);

    switch (number) {
    case SYS_statx: {
        int dirfd = va_arg(ap, int);
        const char *pathname = va_arg(ap, const char *);
        // ... extract remaining args
        expand_chroot_path_at(dirfd, pathname);
        return nextcall(syscall)(number, dirfd, pathname, ...);
    }
    // ... other path-related syscalls
    default:
        // Pass through with 6 args (glibc pattern)
        return nextcall(syscall)(number, a1, a2, a3, a4, a5, a6);
    }
}
```

**Syscalls handled:**

| Syscall | Number (aarch64) | Arguments |
|---------|------------------|-----------|
| `SYS_statx` | 291 | dirfd, pathname, flags, mask, statxbuf |
| `SYS_openat` | 56 | dirfd, pathname, flags, mode |
| `SYS_faccessat` | 48 | dirfd, pathname, mode, flags |
| `SYS_newfstatat` | 79 | dirfd, pathname, statbuf, flags |
| `SYS_readlinkat` | 78 | dirfd, pathname, buf, bufsiz |
| `SYS_unlinkat` | 35 | dirfd, pathname, flags |
| `SYS_mkdirat` | 34 | dirfd, pathname, mode |

**Why extract 6 args in default case?** Glibc's own `syscall()` implementation extracts exactly 6 `va_arg` unconditionally. The kernel expects 6 register arguments (x0-x5 on aarch64) and ignores unused ones.

**Files added:**
- `submodules/fakechroot/src/syscall.c`

**Files modified:**
- `submodules/fakechroot/src/Makefile.am`
- `submodules/fakechroot/configure.ac`

**Result:**
```bash
$ strace -e statx node -e 'require("fs").statSync("/nix/store")'
statx(AT_FDCWD, "/data/data/com.termux.nix/files/usr/nix/store", ...) = 0
# Path correctly translated!
```

---

## Android Seccomp Bypass

Android's seccomp filter blocks several syscalls that cause issues with Nix packages:

| Syscall | Number | Issue | Solution |
|---------|--------|-------|----------|
| `faccessat2` | 439 | Go's `exec.LookPath` uses it | SIGSYS handler returns ENOSYS |
| `clone3` | 435 | glibc's `posix_spawn` uses it | Android glibc patches avoid it |
| `set_robust_list` | 99 | Thread creation | Android glibc patches |
| `rseq` | 293 | Restartable sequences | Android glibc patches |

### How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                    Go Binary (e.g., glab)                    │
│                          │                                   │
│                          ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │         Raw syscall: faccessat2(439)                    ││
│  └─────────────────────────────────────────────────────────┘│
│                          │                                   │
│                          ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │              Android Kernel Seccomp                     ││
│  │         Syscall 439 blocked → Send SIGSYS               ││
│  └─────────────────────────────────────────────────────────┘│
│                          │                                   │
│                          ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │         libfakechroot SIGSYS Handler                    ││
│  │  • Check si_code == SYS_SECCOMP                         ││
│  │  • Check si_syscall == 439 (faccessat2)                 ││
│  │  • Set return value to -ENOSYS in registers             ││
│  │  • Return (syscall appears to have returned ENOSYS)     ││
│  └─────────────────────────────────────────────────────────┘│
│                          │                                   │
│                          ▼                                   │
│  ┌─────────────────────────────────────────────────────────┐│
│  │                Go Runtime                                ││
│  │  • Sees ENOSYS from faccessat2                          ││
│  │  • Falls back to faccessat (syscall 48)                 ││
│  │  • Continues normally                                    ││
│  └─────────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────────┘
```

### sigaction Interception

Go's runtime installs signal handlers early in process startup. To prevent Go from overriding our SIGSYS handler:

```
┌─────────────────────────────────────────────────────────────┐
│                    Process Startup                           │
│                          │                                   │
│ 1. ld.so loads libfakechroot.so (LD_PRELOAD)                │
│                          │                                   │
│ 2. fakechroot_init() runs (constructor)                     │
│    └─ Installs SIGSYS handler via real sigaction()          │
│                          │                                   │
│ 3. Go runtime initializes                                    │
│    └─ Tries to install SIGSYS handler via sigaction()       │
│                          │                                   │
│ 4. Our sigaction wrapper intercepts                          │
│    └─ Saves Go's handler but doesn't install it             │
│    └─ Returns success (Go thinks it worked)                  │
│                          │                                   │
│ 5. SIGSYS arrives (blocked syscall)                          │
│    └─ Our handler runs first                                 │
│    └─ If faccessat2: return ENOSYS                          │
│    └─ Otherwise: chain to Go's saved handler                │
└─────────────────────────────────────────────────────────────┘
```

---

## Build Configuration

### Nix Package

```nix
# common/pkgs/android-fakechroot.nix
{ stdenv, patchelf, fakechroot, androidGlibc, installationDir, src }:
let
  excludePath = "/3rdmodem:/acct:/apex:/android:...";  # Android system paths
  androidGlibcAbs = "${installationDir}${androidGlibc}/lib";
  androidLdso = "${androidGlibcAbs}/ld-linux-aarch64.so.1";
in
fakechroot.overrideAttrs (oldAttrs: {
  pname = "fakechroot-android";
  version = "unstable-local";
  inherit src;
  patches = [];

  nativeBuildInputs = (oldAttrs.nativeBuildInputs or []) ++ [patchelf];

  # Pass Android paths to configure via AC_ARG_VAR environment variables
  # These get written to config.h via AC_DEFINE_UNQUOTED
  ANDROID_ELFLOADER = androidLdso;
  ANDROID_BASE = installationDir;
  ANDROID_EXCLUDE_PATH = excludePath;

  postFixup = (oldAttrs.postFixup or "") + ''
    # Patch binaries to use Android glibc
    for bin in $out/bin/fakechroot $out/bin/ldd.fakechroot; do
      if [ -f "$bin" ]; then
        patchelf --set-interpreter "${androidLdso}" --set-rpath "${androidGlibcAbs}" "$bin"
      fi
    done

    # CRITICAL: Replace standard glibc in libfakechroot.so RPATH with Android glibc
    # This ensures glibc calls (posix_spawn, etc.) use Android glibc
    LIBFAKE="$out/lib/fakechroot/libfakechroot.so"
    if [ -f "$LIBFAKE" ]; then
      OLD_RPATH=$(patchelf --print-rpath "$LIBFAKE")
      NEW_RPATH=$(echo "$OLD_RPATH" | sed 's|/nix/store/[^:]*-glibc-[^:]*/lib|${androidGlibcAbs}|g')
      if [ -n "$NEW_RPATH" ] && [ "$NEW_RPATH" != "$OLD_RPATH" ]; then
        patchelf --set-rpath "$NEW_RPATH" "$LIBFAKE"
      fi
    fi
  '';
})
```

### Compile-Time Constants

These are passed as environment variables to `./configure` and written to `config.h` via `AC_DEFINE_UNQUOTED`:

| Constant | Purpose |
|----------|---------|
| `ANDROID_ELFLOADER` | Path to Android glibc's ld.so |
| `ANDROID_BASE` | Installation prefix (`/data/data/com.termux.nix/files/usr`) |
| `ANDROID_EXCLUDE_PATH` | Paths to exclude from translation (e.g., `/proc:/sys:/dev`) |

The `configure.ac` script handles these via `AC_ARG_VAR`:
```autoconf
AC_ARG_VAR([ANDROID_ELFLOADER], [Path to Android glibc's ld.so dynamic linker])
AC_ARG_VAR([ANDROID_BASE], [Installation prefix for Android])
AC_ARG_VAR([ANDROID_EXCLUDE_PATH], [Colon-separated paths excluded from chroot translation])

if test -n "$ANDROID_BASE"; then
    AC_DEFINE_UNQUOTED([ANDROID_BASE], ["$ANDROID_BASE"], [Installation prefix])
fi
# ... similar for other variables
```

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

### posix_spawn Fails with SIGSYS (Exit Code 159)

**Symptom:**
```bash
# Python subprocess fails
$ python3 -c "import subprocess; subprocess.run(['bash', '-c', 'echo hi'])"
# Exit code 159 (SIGSYS - bad system call)

# But os.system works
$ python3 -c "import os; os.system('bash -c \"echo hi\"')"
hi
```

**Cause:** libfakechroot.so is linked against **standard glibc** instead of **Android glibc**. When fakechroot calls `nextcall(posix_spawn)`, it uses standard glibc's implementation which internally uses `clone3` syscall - blocked by Android's seccomp.

**Diagnosis:**
```bash
# Check fakechroot's RUNPATH
readelf -d /path/to/libfakechroot.so | grep RUNPATH

# Bad (standard glibc):
# RUNPATH: [/nix/store/xxx-glibc-2.40-66/lib]

# Good (Android glibc):
# RUNPATH: [/data/data/.../nix/store/xxx-glibc-android-2.40-android/lib]
```

**Root Cause:** The fakechroot Nix build uses `stdenv.mkDerivation` which defaults to standard glibc. When `libfakechroot.so` calls `nextcall(posix_spawn)`, it uses standard glibc's implementation which internally uses `clone3` syscall - blocked by Android's seccomp.

**Fix (Implemented):** Patch `libfakechroot.so`'s RUNPATH in postFixup to prepend Android glibc:
```nix
# In common/overlays/fakechroot.nix postFixup:
LIBFAKE="$out/lib/fakechroot/libfakechroot.so"
NEW_RPATH="${androidGlibcAbs}:$OLD_RPATH"
patchelf --set-rpath "$NEW_RPATH" "$LIBFAKE"
```

This ensures glibc functions (like `posix_spawn`) are resolved from Android glibc first, which uses `clone` instead of `clone3`.

**Verification:**
```bash
# Check RUNPATH includes Android glibc first
readelf -d /path/to/libfakechroot.so | grep RUNPATH
# Should show: /data/data/.../glibc-android-.../lib:/nix/store/...-glibc-2.40-.../lib
```

**Workaround (Python - no longer needed):**
```python
# Force fork+exec instead of posix_spawn
import subprocess
subprocess.run(['cmd'], preexec_fn=lambda: None)  # preexec_fn forces fork mode
```

### Bus Error When Patching Live libfakechroot.so

**Symptom:** After patching `/etc/ld.so.preload` library, all processes crash with bus error

**Cause:** libfakechroot.so is memory-mapped by all running processes. Modifying it corrupts their memory.

**Solution:** Never patch the live preload library. Instead:
1. Build a new version
2. Update ld.so.preload to point to new version
3. Start new shell/processes to use new library

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

### Why dlsym Instead of Symbol Versioning?

GNU symbol versioning (`.symver` directive) does not work for LD_PRELOAD interposition libraries. When using `.symver __real_open, open@@GLIBC_2.17` in a preload library, the linker resolves the versioned reference to the local `open` wrapper instead of leaving it undefined for the real glibc. This causes infinite recursion.

`dlsym(RTLD_NEXT, "open")` is the correct approach for LD_PRELOAD libraries because it explicitly requests the *next* symbol in the library search order, which is the glibc function.
