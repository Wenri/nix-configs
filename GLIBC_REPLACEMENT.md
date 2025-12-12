# glibc Replacement Strategy for nix-on-droid

## The Problem

Android's kernel uses seccomp to block certain syscalls that standard glibc expects to work. Running unpatched glibc binaries on Android causes crashes or hangs because:
- `clone3()` syscall is blocked
- `set_robust_list()` syscall is blocked
- `rseq()` syscall is blocked

Termux solves this by maintaining a patched glibc that disables or works around these blocked syscalls.

## Current Implementation: Build-Time patchelf with Custom Android glibc

The configuration uses a **two-part approach**:

### Part 1: Build Android-patched glibc

We build glibc 2.40 with Termux's Android compatibility patches:
- Located in `common/overlays/glibc.nix`
- Patches in `common/overlays/patches/glibc-termux/`
- Available as `packages.aarch64-linux.androidGlibc`

**Patches Applied:**
1. `disable-clone3.patch` - Disables clone3 syscall (uses fallback)
2. `kernel-features.h.patch` - Android kernel feature flags
3. `set-nptl-syscalls.patch` - Disables set_robust_list and rseq
4. `set-fakesyscalls.patch` - Fake implementations for blocked syscalls
5. Plus 24 other patches for Android compatibility

### Part 2: patchelf-based Binary Patching

Instead of rebuilding all packages with our glibc (which defeats binary cache):
1. Download packages from nixpkgs binary cache
2. Use `patchelf` to rewrite ELF headers:
   - Interpreter → our Android glibc's `ld-linux-aarch64.so.1`
   - RPATH → our Android glibc's lib directory

**Available Functions:**
```nix
# From flake outputs
flake.lib.aarch64-linux.androidGlibc        # The Android-patched glibc
flake.lib.aarch64-linux.patchPackageForAndroidGlibc  # Patch function
```

## Usage

### In nix-on-droid configuration:

```nix
{ patchPackageForAndroidGlibc, pkgs, ... }: {
  environment.packages = map patchPackageForAndroidGlibc [
    pkgs.hello
    pkgs.curl
    pkgs.git
  ];
}
```

### As a standalone package:

```bash
nix build --impure --expr '
let
  flake = builtins.getFlake "/path/to/nix-on-droid";
  patchFn = flake.lib.aarch64-linux.patchPackageForAndroidGlibc;
  pkgs = flake.inputs.nixpkgs.legacyPackages.aarch64-linux;
in
  patchFn pkgs.hello
'
```

### Building just the Android glibc:

```bash
nix build .#androidGlibc
```

## What Gets Built

| Component | Source | Time |
|-----------|--------|------|
| Android glibc | Built from source with patches | ~20 minutes |
| patchelf wrappers | Small derivations, just copies | Seconds |
| Original packages | Binary cache | Downloaded |

## Verification

Check that a patched binary uses Android glibc:

```bash
# Check interpreter
patchelf --print-interpreter result/bin/hello
# Should show: /nix/store/.../glibc-android-2.40-66/lib/ld-linux-aarch64.so.1

# Check RPATH
patchelf --print-rpath result/bin/hello
# Should include: /nix/store/.../glibc-android-2.40-66/lib
```

## Technical Details

### Android Kernel Restrictions (seccomp)

The Android kernel's seccomp filter blocks these syscalls:
- `clone3` (378) - Modern thread/process creation
- `set_robust_list` (99) - Robust futex registration
- `rseq` (293) - Restartable sequences
- Various others (mq_*, syslog, etc.)

### Termux Patch Strategy

1. **clone3**: Disabled at compile time, falls back to clone()
2. **set_robust_list**: Registration disabled, futex still works
3. **rseq**: Always reports registration failed (safe fallback)
4. **Fake syscalls**: Wrapper returns -ENOSYS for blocked syscalls

### Files Structure

```
common/overlays/
 glibc.nix                    # Main glibc overlay
 patches/glibc-termux/
 disable-clone3.patch     # Essential patches   ├
   ├── kernel-features.h.patch
   ├── set-nptl-syscalls.patch
   ├── set-fakesyscalls.patch
   ├── fakesyscall.json         # Syscall→fake mapping
   ├── process-fakesyscalls.sh  # Generate disabled-syscall.h
   └── ... (24 more patches)
```

## Caveats

1. **New store paths**: Patched packages have different paths
2. **Disk space**: Both original + patched versions exist (use `nix-collect-garbage`)
3. **Static binaries**: Won't be patched (they don't use glibc dynamically)
4. **Subprocesses**: May need to inherit LD_LIBRARY_PATH for some tools

## Alternative Approaches (Not Used)

1. **Full overlay**: Replace glibc in overlays → Rebuilds everything
2. **replaceDependencies**: Nix experimental feature → Complex, unreliable
3. **LD_PRELOAD**: Runtime interposition → Doesn't fix interpreter
4. **Termux glibc-runner**: External wrapper → Extra dependency
