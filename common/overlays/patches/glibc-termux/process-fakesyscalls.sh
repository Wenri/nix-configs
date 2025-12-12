#!/usr/bin/env bash
# Helper script to process fakesyscall.json for glibc Android build
# Based on Termux's build.sh

set -e

TERMUX_PKG_SRCDIR="$1"
TERMUX_PKG_BUILDER_DIR="$2"
ARCH="$3"

if [ -z "$TERMUX_PKG_SRCDIR" ] || [ -z "$TERMUX_PKG_BUILDER_DIR" ] || [ -z "$ARCH" ]; then
  echo "Usage: $0 <srcdir> <builder_dir> <arch>"
  exit 1
fi

ARCH_DIR="$TERMUX_PKG_SRCDIR/sysdeps/unix/sysv/linux/$ARCH"

if [ ! -d "$ARCH_DIR" ]; then
  echo "Architecture directory not found: $ARCH_DIR"
  exit 1
fi

# Backup original syscall.S
if [ -f "$ARCH_DIR/syscall.S" ]; then
  mv "$ARCH_DIR/syscall.S" "$ARCH_DIR/syscallS.S"
fi

# Create disabled-syscall.h header
HEADER_FILE="$ARCH_DIR/disabled-syscall.h"
echo "/* Disabled syscalls for Android */" > "$HEADER_FILE"

# Extract syscall numbers from fakesyscall.json and remove them from arch-syscall.h
if [ -f "$ARCH_DIR/arch-syscall.h" ]; then
  for syscall in $(jq -r '.[] | .[]' "$TERMUX_PKG_BUILDER_DIR/fakesyscall.json" | grep -v '^[0-9]\+$'); do
    if grep -q "#define __NR_$syscall " "$ARCH_DIR/arch-syscall.h"; then
      sed -i "/#define __NR_$syscall /d" "$ARCH_DIR/arch-syscall.h"
      echo "#define __NR_$syscall DISABLED" >> "$HEADER_FILE"
    fi
  done
fi

# Generate DISABLED_SYSCALL_WITH_FAKESYSCALL macro
echo "" >> "$HEADER_FILE"
echo "#define DISABLED_SYSCALL_WITH_FAKESYSCALL \\" >> "$HEADER_FILE"

for fakesyscall in $(jq -r '. | keys | .[]' "$TERMUX_PKG_BUILDER_DIR/fakesyscall.json"); do
  need_return=false
  for syscall in $(jq -r '."'"$fakesyscall"'" | .[]' "$TERMUX_PKG_BUILDER_DIR/fakesyscall.json"); do
    if grep -q "^#define __NR_$syscall DISABLED" "$HEADER_FILE" || echo "$syscall" | grep -q '^[0-9]\+$'; then
      if echo "$syscall" | grep -q '^[0-9]\+$'; then
        echo -e "\tcase $syscall: \\" >> "$HEADER_FILE"
      else
        echo -e "\tcase __NR_$syscall: \\" >> "$HEADER_FILE"
      fi
      need_return=true
    fi
  done
  if [ "$need_return" = "true" ]; then
    echo -e "\t\treturn $fakesyscall; \\" >> "$HEADER_FILE"
  fi
done

# Remove trailing backslash
sed -i '$ s| \\||' "$HEADER_FILE"
