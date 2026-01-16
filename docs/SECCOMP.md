# Seccomp on Android (nix-on-droid)

This document describes seccomp capabilities and techniques for handling blocked syscalls on Android, specifically for the nix-on-droid environment.

## Overview

Android uses seccomp-bpf to restrict syscalls available to applications. This causes issues for Nix packages that use newer syscalls like `clone3`, `faccessat2`, `rseq`, and `set_robust_list`.

## Available Seccomp Features (Android 5.10.43)

Testing on the nix-on-droid environment reveals the following capabilities:

### Basic Support
| Feature | Status |
|---------|--------|
| PR_SET_NO_NEW_PRIVS | ✅ Available |
| SECCOMP_MODE_FILTER (prctl) | ✅ Available |
| SECCOMP_MODE_FILTER (seccomp syscall) | ✅ Available |
| Stacking filters | ✅ Available |

### Return Actions (SECCOMP_GET_ACTION_AVAIL)
| Action | Status | Description |
|--------|--------|-------------|
| SECCOMP_RET_KILL_PROCESS | ✅ | Kill entire process |
| SECCOMP_RET_KILL_THREAD | ✅ | Kill thread |
| SECCOMP_RET_TRAP | ✅ | Send SIGSYS signal |
| SECCOMP_RET_ERRNO | ✅ | Return errno to caller |
| SECCOMP_RET_USER_NOTIF | ✅ | Forward to supervisor process |
| SECCOMP_RET_TRACE | ✅ | Notify ptrace tracer |
| SECCOMP_RET_LOG | ✅ | Log and allow |
| SECCOMP_RET_ALLOW | ✅ | Allow syscall |

### Filter Flags
| Flag | Status |
|------|--------|
| SECCOMP_FILTER_FLAG_TSYNC | ✅ Available |
| SECCOMP_FILTER_FLAG_LOG | ✅ Available |
| SECCOMP_FILTER_FLAG_SPEC_ALLOW | ✅ Available |
| SECCOMP_FILTER_FLAG_NEW_LISTENER | ✅ Available |
| SECCOMP_FILTER_FLAG_TSYNC_ESRCH | ✅ Available |
| SECCOMP_FILTER_FLAG_WAIT_KILLABLE_RECV | ❌ Not available |

## Key Findings

### 1. Android's Existing Filter Returns ENOSYS

Android already has a seccomp filter installed (mode 2) that returns `ENOSYS` for blocked syscalls like `faccessat2`, `rseq`, `clone3`, and `set_robust_list`. This is better than killing the process - programs can fall back to alternative syscalls.

```c
// Current seccomp mode on Android
int mode = prctl(PR_GET_SECCOMP);  // Returns 2 (filter mode)
```

### 2. Filters Can Be Stacked

Additional seccomp filters can be installed on top of Android's existing filter. Filters are additive - the most restrictive action wins.

### 3. Seccomp Filters Are Permanent

Once installed, a seccomp filter **cannot be removed or bypassed** by the filtered process. The only ways to execute a blocked syscall are:

1. **Have a separate supervisor process** that doesn't have the filter
2. **Use USER_NOTIF** to forward syscalls to a supervisor

## Techniques for Handling Blocked Syscalls

### Option 1: SECCOMP_RET_ERRNO Wrapper (Simplest)

For static binaries that don't handle `ENOSYS` gracefully, a wrapper can install a filter that explicitly returns `ENOSYS` before exec:

```c
// Wrapper installs filter, then execs target binary
prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
seccomp(SECCOMP_SET_MODE_FILTER, 0, &errno_filter);
execvp(target_binary, argv);
```

**Pros:** Simple, no binary modification needed
**Cons:** Syscall still fails (just gracefully)

See: `scripts/seccomp/seccomp-wrapper.c`

### Option 2: SECCOMP_RET_USER_NOTIF Supervisor (Most Powerful)

A supervisor process can intercept blocked syscalls and **actually execute them**:

```
Target Process                    Supervisor Process
(has seccomp filter)              (NO filter - can do anything)
      |                                   |
      | syscall(blocked)                  |
      |--------- notif_fd --------------->|
      |                                   | syscall(real)
      |                                   |
      |<-------- response ----------------|
      | (returns result)
```

**Key Points:**
- Fork **before** installing the filter
- Supervisor receives notification fd via SCM_RIGHTS
- Supervisor executes the real syscall and returns the result
- Target process sees the syscall succeed

**Pros:** Full syscall emulation, works for any syscall
**Cons:** Requires supervisor process, more complex

See: `scripts/seccomp/seccomp-supervisor-demo.c`

### Option 3: SECCOMP_RET_TRAP + SIGSYS Handler (Dynamic Binaries)

For dynamically linked binaries, install a SIGSYS handler via LD_PRELOAD:

```c
void sigsys_handler(int sig, siginfo_t *info, void *ctx) {
    // Handle blocked syscall, modify return value in ucontext
}
```

**Pros:** Works with existing LD_PRELOAD infrastructure (fakechroot)
**Cons:** Cannot call the original syscall from handler (would trigger SIGSYS again)

This is currently used in nix-on-droid's fakechroot for `faccessat2`.

### Option 4: ptrace-based Interception

Use `SECCOMP_RET_TRACE` with ptrace to intercept syscalls:

```c
ptrace(PTRACE_SETOPTIONS, pid, 0, PTRACE_O_TRACESYSGOOD);
// Tracer can modify syscall arguments and return values
```

**Pros:** Full control
**Cons:** Significant performance overhead (like proot)

## For Static Binaries

Static binaries present a challenge because:
1. LD_PRELOAD doesn't work (no dynamic linker)
2. Can't inject SIGSYS handler at runtime

**Solutions:**
1. **USER_NOTIF supervisor** - Best option if available
2. **Wrapper with SECCOMP_RET_ERRNO** - If binary handles ENOSYS
3. **Binary patching** - Modify the binary to include handler (complex)
4. **Rebuild as dynamic** - If source is available

## Implementation in nix-on-droid

Current approach uses:
1. **Android glibc patches** - Disable blocked syscalls at glibc level
2. **Fakechroot with SIGSYS handler** - Catch remaining blocked syscalls
3. **sigaction wrapper** - Prevent Go runtime from overriding SIGSYS handler

For static binaries that still fail, consider:
1. Using the USER_NOTIF supervisor approach
2. Running via the SECCOMP_RET_ERRNO wrapper

## Demo Code

Working examples are in `scripts/seccomp/`:

- **seccomp-wrapper.c** - Wrapper that returns ENOSYS for blocked syscalls
- **seccomp-supervisor-demo.c** - USER_NOTIF supervisor that executes real syscalls

### Building

```bash
cd ~/.config/nix-on-droid/scripts/seccomp
gcc -o seccomp-wrapper seccomp-wrapper.c -Wall
gcc -o seccomp-supervisor-demo seccomp-supervisor-demo.c -Wall
```

### Running

```bash
# Wrapper (returns ENOSYS for blocked syscalls)
./seccomp-wrapper ./some-static-binary

# Supervisor demo (shows USER_NOTIF in action)
./seccomp-supervisor-demo
```

## References

- [Seccomp BPF documentation](https://www.kernel.org/doc/html/latest/userspace-api/seccomp_filter.html)
- [Seccomp user notification](https://man7.org/linux/man-pages/man2/seccomp_unotify.2.html)
- [Android seccomp policy](https://android.googlesource.com/platform/bionic/+/master/libc/SECCOMP_BLOCKLIST.md)
