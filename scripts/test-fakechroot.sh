#!/system/bin/sh
# Diagnostic script to test glibc redirection
set -x

PREFIX="/data/data/com.termux.nix/files/usr"
STORE="$PREFIX/nix/store"
SCRIPT_DIR="/data/data/com.termux.nix/files/home/.config/nix-on-droid/scripts"

# Android glibc (our patched version)
ANDROID_GLIBC_STORE="lb0hd462xiicipri33q3idk43nzz0983-glibc-android-2.40-66"
LD_LINUX="$STORE/$ANDROID_GLIBC_STORE/lib/ld-linux-aarch64.so.1"

# Standard glibc (what binary cache packages reference)
STANDARD_GLIBC_STORE="89n0gcl1yjp37ycca45rn50h7lms5p6f-glibc-2.40-66"

# Other packages
FAKECHROOT_LIB="$STORE/519zc2mj7d6m50z81ywwcp98hh1lpmrm-fakechroot-unstable-2021-02-26/lib/fakechroot/libfakechroot.so"
AUDIT_LIB="$SCRIPT_DIR/pack-audit.so"
TRUE_BIN="$STORE/d9jxdwalyr5qzmyz9m5avmzn7w40h7iy-coreutils-9.8/bin/true"

# Environment for audit module
export FAKECHROOT_BASE="$PREFIX"
export STANDARD_GLIBC="$STANDARD_GLIBC_STORE"
export ANDROID_GLIBC="$ANDROID_GLIBC_STORE"
export PACK_AUDIT_DEBUG=1

echo "=== Test 1: ld.so --help ==="
"$LD_LINUX" --help > /dev/null && echo "PASS" || echo "FAIL"

echo ""
echo "=== Test 2: ld.so true (no audit, no preload) ==="
"$LD_LINUX" "$TRUE_BIN" && echo "PASS" || echo "FAIL: $?"

echo ""
echo "=== Test 3: ld.so --audit true (audit only, with glibc redirect) ==="
"$LD_LINUX" --audit "$AUDIT_LIB" "$TRUE_BIN" && echo "PASS" || echo "FAIL: $?"

echo ""
echo "=== Test 4: ld.so --preload true (preload only, no audit) ==="
"$LD_LINUX" --preload "$FAKECHROOT_LIB" "$TRUE_BIN" && echo "PASS" || echo "FAIL: $?"

echo ""
echo "=== Test 5: ld.so --audit --preload true (both) ==="
"$LD_LINUX" --audit "$AUDIT_LIB" --preload "$FAKECHROOT_LIB" "$TRUE_BIN" && echo "PASS" || echo "FAIL: $?"

echo ""
echo "=== Environment variables for glibc redirection ==="
echo "STANDARD_GLIBC=$STANDARD_GLIBC"
echo "ANDROID_GLIBC=$ANDROID_GLIBC"
