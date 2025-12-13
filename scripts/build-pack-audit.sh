#!/usr/bin/env bash
# Build pack-audit.so linked against Android glibc
#
# This ensures the audit library is self-consistent with the ld.so that loads it.
# Without this, pack-audit.so linked to standard glibc would be loaded by
# Android glibc's ld.so, causing potential ABI mismatches.

set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STORE="/data/data/com.termux.nix/files/usr/nix/store"

# These hashes must match login-fakechroot-orig
ANDROID_GLIBC_STORE="lb0hd462xiicipri33q3idk43nzz0983-glibc-android-2.40-66"

# Paths
ANDROID_GLIBC="$STORE/$ANDROID_GLIBC_STORE"
ANDROID_LD="$ANDROID_GLIBC/lib/ld-linux-aarch64.so.1"

# Find gcc in nix store
GCC_PATH=$(dirname "$(command -v gcc)")
GCC_LIB=$(dirname "$GCC_PATH")/../lib/gcc

echo "=== Building pack-audit.so linked against Android glibc ==="
echo "Android glibc: $ANDROID_GLIBC"
echo "Source: $SCRIPT_DIR/pack-audit.c"

# Compile pack-audit.c with explicit Android glibc paths
# -nostdlib: Don't link standard libraries automatically
# -Wl,--dynamic-linker: Set the ELF interpreter to Android glibc
# -Wl,-rpath: Set RUNPATH to Android glibc
gcc -shared -fPIC -O2 -Wall \
    -Wl,--dynamic-linker="$ANDROID_LD" \
    -Wl,-rpath,"$ANDROID_GLIBC/lib" \
    -o "$SCRIPT_DIR/pack-audit.so" \
    "$SCRIPT_DIR/pack-audit.c" \
    -L"$ANDROID_GLIBC/lib" \
    -ldl

# Use patchelf to ensure RUNPATH only contains Android glibc
# (gcc may add additional paths from the build environment)
echo "Cleaning RUNPATH with patchelf..."
patchelf --set-rpath "$ANDROID_GLIBC/lib" "$SCRIPT_DIR/pack-audit.so"

echo ""
echo "=== Build complete ==="
echo "Output: $SCRIPT_DIR/pack-audit.so"
echo ""
echo "Verifying linkage:"
readelf -d "$SCRIPT_DIR/pack-audit.so" | grep -E "(NEEDED|RUNPATH|RPATH)"
echo ""
echo "Library dependencies:"
ldd "$SCRIPT_DIR/pack-audit.so" 2>&1 || true
