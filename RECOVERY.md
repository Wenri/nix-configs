# replaceAndroidDependencies Implementation - COMPLETED

This document records the successful implementation of environment-level Android patching.

## Summary

Implemented `replaceAndroidDependencies` function that patches all ELF binaries in the nix-on-droid
environment at once, similar to NixOS's `replaceDependencies` but using patchelf.

## Implementation Details

### Key Design Decisions

1. **Selective Symlink Dereferencing**: Instead of `cp -rL` (which is slow for large environments),
   use `cp -r` to preserve symlinks, then selectively dereference only ELF files.

2. **Android Path Handling**: Symlinks to Android paths (glibc compat symlinks) are made absolute
   and kept as symlinks.

3. **ELF Patching**: All ELF binaries get their interpreter and RPATH updated to use Android glibc.

4. **Go Binary Skip**: Go binaries are detected by "Go build" string and skipped (they work fine
   with standard glibc on Android).

### Files Modified

- `common/modules/android/android-integration.nix` - Core `replaceAndroidDependencies` function
- `common/overlays/glibc.nix` - Single output mode for glibc
- `common/pkgs/default.nix` - Uses `builtins.storePath` for existing glibc
- `submodules/nix-on-droid/modules/environment/path.nix` - Updated profile removal for new nix format
- `submodules/nix-on-droid/modules/build/config.nix` - Added `replaceAndroidDependencies` option

### Profile Naming

The patched environment is named `nix-on-droid-path-android` (with `-android` suffix) to
distinguish it from the unpatched environment.

## Completed Tasks

- [x] Created `replaceAndroidDependencies` function
- [x] Modified `path.nix` to support environment-level patching
- [x] Used existing glibc store path via `builtins.storePath`
- [x] Fixed symlink handling - dereference only ELF files
- [x] Updated profile removal for new nix profile list format
- [x] Successfully switched to new configuration

## Verification

After switch, all binaries use the Android glibc interpreter:
```
$ patchelf --print-interpreter ~/.nix-profile/bin/bash
/data/data/com.termux.nix/files/usr/nix/store/6mjpqffiqrgqc80d3f54j5hxcj2dl0aj-glibc-android-2.40-android/lib/ld-linux-aarch64.so.1
```
