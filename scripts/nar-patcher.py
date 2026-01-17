#!/usr/bin/env python3
"""
NAR Patcher - Patch Nix archives for Android compatibility

Reads NAR from stdin, patches for Android, writes NAR to stdout.
- Rewrites symlink targets: /nix/store -> ${prefix}/nix/store
- Patches ELF interpreter and RPATH
- Patches script shebangs

Usage: nix-store --dump /path | nar-patcher.py --prefix /data/.../usr | nix-store --restore $out
"""

import argparse
import os
import struct
import subprocess
import sys
import tempfile
from pathlib import Path


class NarReader:
    """Read NAR format from a file-like object."""

    def __init__(self, f):
        self.f = f

    def read_bytes(self, n):
        data = self.f.read(n)
        if len(data) != n:
            raise ValueError(f"Unexpected EOF: wanted {n}, got {len(data)}")
        return data

    def read_int(self):
        return struct.unpack('<Q', self.read_bytes(8))[0]

    def read_str(self):
        length = self.read_int()
        data = self.read_bytes(length)
        # Padding to 8-byte boundary
        pad = (8 - length % 8) % 8
        if pad:
            self.read_bytes(pad)
        return data

    def read_str_match(self, expected):
        s = self.read_str()
        if s != expected:
            raise ValueError(f"Expected {expected!r}, got {s!r}")


class NarWriter:
    """Write NAR format to a file-like object."""

    def __init__(self, f):
        self.f = f

    def write_bytes(self, data):
        self.f.write(data)

    def write_int(self, n):
        self.write_bytes(struct.pack('<Q', n))

    def write_str(self, s):
        if isinstance(s, str):
            s = s.encode('utf-8')
        self.write_int(len(s))
        self.write_bytes(s)
        # Padding to 8-byte boundary
        pad = (8 - len(s) % 8) % 8
        if pad:
            self.write_bytes(b'\x00' * pad)


class NarPatcher:
    """Patch NAR archives for Android compatibility."""

    def __init__(self, prefix, glibc_path, gcc_lib_path, old_glibc, old_gcc_lib):
        self.prefix = prefix
        self.glibc_path = glibc_path
        self.gcc_lib_path = gcc_lib_path
        self.old_glibc = old_glibc
        self.old_gcc_lib = old_gcc_lib
        self.interpreter = f"{prefix}{glibc_path}/lib/ld-linux-aarch64.so.1"

    def patch_symlink_target(self, target):
        """Rewrite symlink target for Android."""
        if isinstance(target, bytes):
            target = target.decode('utf-8')

        # Skip if already has prefix
        if target.startswith(self.prefix):
            return target.encode('utf-8')

        # Add prefix to /nix/store paths
        if target.startswith('/nix/store'):
            return f"{self.prefix}{target}".encode('utf-8')

        return target.encode('utf-8') if isinstance(target, str) else target

    def patch_script(self, content):
        """Patch shebang in scripts."""
        if isinstance(content, bytes):
            # Check for shebang
            if not content.startswith(b'#!'):
                return content

            # Find end of first line
            newline = content.find(b'\n')
            if newline == -1:
                newline = len(content)

            shebang = content[:newline]
            rest = content[newline:]

            # Skip if already prefixed
            if self.prefix.encode() in shebang:
                return content

            # Replace /nix/store in shebang
            if b'/nix/store' in shebang:
                new_shebang = shebang.replace(b'/nix/store', f"{self.prefix}/nix/store".encode())
                return new_shebang + rest

        return content

    def patch_elf(self, content):
        """Patch ELF interpreter and RPATH using patchelf."""
        # Check ELF magic
        if len(content) < 4 or content[:4] != b'\x7fELF':
            return content

        # Check if dynamically linked (has PT_INTERP or PT_DYNAMIC)
        # Simple heuristic: check for .dynamic section marker
        if b'.dynamic' not in content and b'.interp' not in content:
            return content

        # Write to temp file, patch, read back
        with tempfile.NamedTemporaryFile(delete=False, suffix='.elf') as tmp:
            tmp.write(content)
            tmp_path = tmp.name

        try:
            os.chmod(tmp_path, 0o755)

            patchelf_args = []

            # Check and set interpreter
            try:
                result = subprocess.run(
                    ['patchelf', '--print-interpreter', tmp_path],
                    capture_output=True, text=True
                )
                if result.returncode == 0:
                    interp = result.stdout.strip()
                    if interp and self.prefix not in interp:
                        patchelf_args.extend(['--set-interpreter', self.interpreter])
            except Exception:
                pass

            # Check and set RPATH
            try:
                result = subprocess.run(
                    ['patchelf', '--print-rpath', tmp_path],
                    capture_output=True, text=True
                )
                if result.returncode == 0:
                    rpath = result.stdout.strip()
                    if rpath and '/nix/store' in rpath:
                        # Replace glibc and gcc-lib paths
                        new_rpath = rpath
                        if self.old_glibc:
                            new_rpath = new_rpath.replace(self.old_glibc, self.glibc_path)
                        if self.old_gcc_lib:
                            new_rpath = new_rpath.replace(self.old_gcc_lib, self.gcc_lib_path)

                        # Add prefix to remaining /nix/store paths
                        # Only at path boundaries to avoid double-prefixing
                        if new_rpath.startswith('/nix/store'):
                            new_rpath = self.prefix + new_rpath
                        new_rpath = new_rpath.replace(':/nix/store', f':{self.prefix}/nix/store')

                        if new_rpath != rpath:
                            patchelf_args.extend(['--set-rpath', new_rpath])
            except Exception:
                pass

            # Apply patches
            if patchelf_args:
                try:
                    subprocess.run(
                        ['patchelf'] + patchelf_args + [tmp_path],
                        check=True, capture_output=True
                    )
                except subprocess.CalledProcessError:
                    pass  # Ignore patchelf failures (static binaries, etc.)

            # Read back
            with open(tmp_path, 'rb') as f:
                return f.read()
        finally:
            os.unlink(tmp_path)

    def process(self, reader, writer):
        """Process NAR: read, patch, write."""
        # Header
        reader.read_str_match(b'nix-archive-1')
        writer.write_str(b'nix-archive-1')

        self._process_node(reader, writer, '')

    def _process_node(self, reader, writer, path):
        """Process a single NAR node."""
        reader.read_str_match(b'(')
        writer.write_str(b'(')

        reader.read_str_match(b'type')
        writer.write_str(b'type')

        node_type = reader.read_str()
        writer.write_str(node_type)

        if node_type == b'regular':
            self._process_regular(reader, writer, path)
        elif node_type == b'symlink':
            self._process_symlink(reader, writer, path)
        elif node_type == b'directory':
            self._process_directory(reader, writer, path)
        else:
            raise ValueError(f"Unknown node type: {node_type!r}")

        # Directory processing consumes the ) when it sees end of entries
        if hasattr(self, '_pending_close') and self._pending_close:
            self._pending_close = False
        else:
            reader.read_str_match(b')')
        writer.write_str(b')')

    def _process_regular(self, reader, writer, path):
        """Process a regular file."""
        executable = False

        # Check for executable marker
        marker = reader.read_str()
        if marker == b'executable':
            executable = True
            writer.write_str(b'executable')
            reader.read_str_match(b'')  # empty string after executable
            writer.write_str(b'')
            marker = reader.read_str()

        if marker != b'contents':
            raise ValueError(f"Expected 'contents', got {marker!r}")

        # Read content
        content = reader.read_str()

        # Patch content
        if content.startswith(b'#!'):
            content = self.patch_script(content)
        elif content.startswith(b'\x7fELF'):
            content = self.patch_elf(content)

        writer.write_str(b'contents')
        writer.write_str(content)

    def _process_symlink(self, reader, writer, path):
        """Process a symlink."""
        reader.read_str_match(b'target')
        writer.write_str(b'target')

        target = reader.read_str()
        new_target = self.patch_symlink_target(target)
        writer.write_str(new_target)

    def _process_directory(self, reader, writer, path):
        """Process a directory."""
        while True:
            # Peek at next token
            marker = reader.read_str()

            # ) means end of directory entries - don't consume, let parent handle
            if marker == b')':
                # We've consumed the ), but parent expects to read it
                # So we use a flag to indicate we've seen it
                self._pending_close = True
                return

            if marker != b'entry':
                raise ValueError(f"Expected 'entry' or ')', got {marker!r}")

            writer.write_str(b'entry')

            reader.read_str_match(b'(')
            writer.write_str(b'(')

            reader.read_str_match(b'name')
            writer.write_str(b'name')

            name = reader.read_str()
            writer.write_str(name)

            reader.read_str_match(b'node')
            writer.write_str(b'node')

            self._process_node(reader, writer, f"{path}/{name.decode('utf-8')}")

            reader.read_str_match(b')')
            writer.write_str(b')')


def main():
    parser = argparse.ArgumentParser(description='Patch NAR for Android')
    parser.add_argument('--prefix', required=True, help='Android installation prefix')
    parser.add_argument('--glibc', required=True, help='Android glibc store path')
    parser.add_argument('--gcc-lib', required=True, help='Android gcc-lib store path')
    parser.add_argument('--old-glibc', default='', help='Standard glibc to replace')
    parser.add_argument('--old-gcc-lib', default='', help='Standard gcc-lib to replace')
    args = parser.parse_args()

    # Use binary mode for stdin/stdout
    stdin = sys.stdin.buffer
    stdout = sys.stdout.buffer

    reader = NarReader(stdin)
    writer = NarWriter(stdout)

    patcher = NarPatcher(
        prefix=args.prefix,
        glibc_path=args.glibc,
        gcc_lib_path=args.gcc_lib,
        old_glibc=args.old_glibc,
        old_gcc_lib=args.old_gcc_lib
    )

    patcher.process(reader, writer)


if __name__ == '__main__':
    main()
