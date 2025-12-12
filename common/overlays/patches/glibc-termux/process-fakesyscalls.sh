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

# Create disabled-syscall.h header by moving syscall definitions from arch-syscall.h
HEADER_FILE="$ARCH_DIR/disabled-syscall.h"
echo "/* Disabled syscalls for Android - definitions moved from arch-syscall.h */" > "$HEADER_FILE"

# Extract syscall definitions from arch-syscall.h and move them to disabled-syscall.h
if [ -f "$ARCH_DIR/arch-syscall.h" ]; then
  for syscall in $(jq -r '.[] | .[]' "$TERMUX_PKG_BUILDER_DIR/fakesyscall.json" 2>/dev/null); do
    # Skip numeric entries
    if [[ "$syscall" =~ ^[0-9]+$ ]]; then
      continue
    fi
    # Copy the #define line to disabled-syscall.h, then remove from arch-syscall.h
    if grep -q "#define __NR_$syscall " "$ARCH_DIR/arch-syscall.h"; then
      grep "#define __NR_$syscall " "$ARCH_DIR/arch-syscall.h" >> "$HEADER_FILE" || true
      sed -i "/#define __NR_$syscall /d" "$ARCH_DIR/arch-syscall.h"
    fi
  done
fi

# Generate DISABLED_SYSCALL_WITH_FAKESYSCALL macro for the syscall() wrapper
{
  echo ""
  echo "#define DISABLED_SYSCALL_WITH_FAKESYSCALL \\"

  for fakesyscall in $(jq -r '. | keys | .[]' "$TERMUX_PKG_BUILDER_DIR/fakesyscall.json" 2>/dev/null); do
    need_return=false
    for syscall in $(jq -r '."'"$fakesyscall"'" | .[]' "$TERMUX_PKG_BUILDER_DIR/fakesyscall.json" 2>/dev/null); do
      if [[ "$syscall" =~ ^[0-9]+$ ]]; then
        echo -e "\tcase $syscall: \\"
        need_return=true
      elif grep -q "^#define __NR_$syscall " "$HEADER_FILE"; then
        echo -e "\tcase __NR_$syscall: \\"
        need_return=true
      fi
    done
    if [ "$need_return" = "true" ]; then
      echo -e "\t\treturn $fakesyscall; \\"
    fi
  done
} >> "$HEADER_FILE"

# Remove trailing backslash from last line
sed -i '$ s| \\||' "$HEADER_FILE"

echo "✓ Created disabled-syscall.h"
