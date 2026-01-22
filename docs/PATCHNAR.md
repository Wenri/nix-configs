# patchnar: NAR Stream Patcher

> **Last Updated:** January 22, 2026
> **Version:** 0.22.0
> **Based on:** patchelf

## Table of Contents

1. [Overview](#overview)
2. [How It Works](#how-it-works)
3. [Command-Line Options](#command-line-options)
4. [String-Aware Patching](#string-aware-patching)
5. [Integration with NixOS-style Grafting](#integration-with-nixos-style-grafting)
6. [Building](#building)
7. [Examples](#examples)

---

## Overview

patchnar is a NAR (Nix Archive) stream patcher designed for Android compatibility. It processes NAR streams from stdin to stdout, modifying ELF binaries, symlinks, and scripts without unpacking to disk. This enables efficient patching of packages from the Nix binary cache at install time.

**Key Features:**
- Stream-based processing (no disk I/O for intermediate files)
- ELF binary patching (interpreter, RPATH)
- Symlink target patching
- Script shebang patching
- **String-aware source patching** (new in v0.22.0) using GNU Source-highlight
  - Automatic language detection from filename (100+ languages supported)
  - Patches paths only inside string literals (avoids comments, variable expansions)
- Hash mapping for inter-package reference substitution
- Based on patchelf with NAR stream support

---

## How It Works

### NAR Stream Processing

patchnar reads NAR streams from stdin and writes patched NAR streams to stdout:

```
nix-store --dump /nix/store/xxx-package | patchnar [OPTIONS] | nix-store --restore $out
```

The NAR format contains:
- File contents (with executable flag)
- Symlink targets
- Directory structure

patchnar intercepts file contents and symlink targets, applying patches as needed.

### What Gets Patched

| Content Type | Patches Applied |
|--------------|-----------------|
| **ELF binaries** | Interpreter path, RPATH entries |
| **Scripts** | Shebang line, string literals (auto-detected language) |
| **Source files** | String literals (language detected from filename) |
| **Symlinks** | Target paths pointing to `/nix/store/` |
| **All content** | Hash mapping substitution for inter-package references |

### Patch Order

For each content type, patches are applied in this order:

1. **glibc substitution** - Replace standard glibc with Android glibc
2. **Hash mapping** - Replace old package hashes with new ones
3. **Prefix addition** - Add Android prefix to `/nix/store/` paths

This order is critical because hash mapping would prevent glibc matching if done first.

---

## Command-Line Options

```
Usage: patchnar [OPTIONS]

Patch NAR stream for Android compatibility.
Reads NAR from stdin, writes patched NAR to stdout.

Options:
  --prefix PATH        Installation prefix (e.g., /data/.../usr)
  --glibc PATH         Android glibc store path
  --old-glibc PATH     Original glibc store path to replace
  --mappings FILE      Hash mappings file for inter-package refs
                       Format: OLD_PATH NEW_PATH (one per line)
  --self-mapping MAP   Self-reference mapping (format: "OLD_PATH NEW_PATH")
  --add-prefix-to PATH Path pattern to add prefix to in script strings
                       (e.g., /nix/var/). Can be specified multiple times.
  --source-highlight-data-dir DIR
                       Path to source-highlight data files (.lang files)
  --debug              Enable debug output
  --help               Show this help
```

### Required Options

- `--prefix`: The Android installation prefix (e.g., `/data/data/com.termux.nix/files/usr`)

### ELF Patching Options

- `--glibc`: Path to Android glibc (the replacement)
- `--old-glibc`: Path to standard glibc (to be replaced)

### Hash Mapping Options

- `--mappings FILE`: File containing hash mappings (one per line: `OLD_PATH NEW_PATH`)
- `--self-mapping MAP`: Single mapping for self-references

### String-Aware Patching Options (v0.22.0+)

- `--add-prefix-to PATH`: Additional path patterns to prefix in script strings
- `--source-highlight-data-dir DIR`: Path to source-highlight `.lang` files

---

## String-Aware Patching

### The Problem

Some source files contain hardcoded paths like `/nix/var/nix/profiles/default` that need the Android prefix. However, simply searching and replacing all occurrences could patch:
- Comments (shouldn't be patched)
- Variable-concatenated paths like `$PREFIX/nix/var/` (already prefixed)

### The Solution

patchnar v0.22.0 uses [GNU Source-highlight](https://www.gnu.org/software/src-highlite/) to tokenize source files and identify string literal regions. Paths are only patched when they appear inside string literals.

**Key feature:** patchnar uses **automatic language detection** via source-highlight's LangMap. The language is detected from the filename extension or name (e.g., `.sh` → shell, `.py` → Python, `Makefile` → makefile). This means patchnar can correctly handle string literals in **any language** that source-highlight supports (100+ languages including shell, Python, Perl, Ruby, C, C++, Java, JavaScript, etc.).

### How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│ Input: Source file content + filename                            │
├─────────────────────────────────────────────────────────────────┤
│                         │                                        │
│                         ▼                                        │
│     LangMap detects language from filename                       │
│     (e.g., "nix.sh" → sh.lang, "config.py" → python.lang)       │
│                         │                                        │
│                         ▼                                        │
│     Source-highlight tokenizes with detected language            │
│                         │                                        │
│                         ▼                                        │
│     StringCapture formatter records "string" token positions     │
│                         │                                        │
│                         ▼                                        │
│     patchnar patches /nix/var/ only inside string regions        │
│                         │                                        │
│                         ▼                                        │
│ Output: Patched source with correct prefixes                     │
└─────────────────────────────────────────────────────────────────┘
```

### Supported Languages

Source-highlight supports 100+ languages. Common ones include:
- Shell scripts (`.sh`, `.bash`, `.zsh`)
- Python (`.py`)
- Perl (`.pl`, `.pm`)
- Ruby (`.rb`)
- C/C++ (`.c`, `.h`, `.cpp`, `.hpp`)
- Java (`.java`)
- JavaScript (`.js`)
- Makefiles (`Makefile`, `makefile`)
- And many more...

### Example

**Input script (nix.sh):**
```bash
#!/bin/sh
export NIX_PROFILES="/nix/var/nix/profiles/default $NIX_LINK"
# /nix/var/in/comment should NOT be patched
echo $PREFIX/nix/var/should/NOT/patch
VAR="/nix/var/should/patch"
```

**After patching with `--add-prefix-to /nix/var/`:**
```bash
#!/bin/sh
export NIX_PROFILES="/data/.../nix/var/nix/profiles/default $NIX_LINK"
# /nix/var/in/comment should NOT be patched
echo $PREFIX/nix/var/should/NOT/patch
VAR="/data/.../nix/var/should/patch"
```

**What was patched:**
- Line 2: `/nix/var/nix/profiles/default` (inside double-quoted string)
- Line 5: `/nix/var/should/patch` (inside double-quoted string)

**What was NOT patched:**
- Line 3: Comment (not a string literal)
- Line 4: After `$PREFIX` variable (would result in double-prefix)

---

## Integration with NixOS-style Grafting

patchnar is used by `replaceAndroidDependencies` for recursive dependency patching:

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    replaceAndroidDependencies                    │
├─────────────────────────────────────────────────────────────────┤
│  1. IFD with exportReferencesGraph discovers full closure       │
│  2. Fixed-point memo recursively patches each package            │
│  3. Hash mappings track old->new store path relationships        │
│  4. patchnar processes each NAR stream                           │
└─────────────────────────────────────────────────────────────────┘
```

### Usage in Nix

```nix
# In android-integration.nix
replaceAndroidDependencies = drv: { addPrefixToPaths ? [] }:
  replaceAndroidDepsLib {
    inherit drv addPrefixToPaths;
    prefix = installationDir;
    androidGlibc = glibc;
    inherit standardGlibc;
    cutoffPackages = [ glibc ];
  };

# In path.nix
patchedEnv = buildCfg.replaceAndroidDependencies baseEnv {
  addPrefixToPaths = [ "/nix/var/" ];
};
```

### Mappings File Format

```
/nix/store/abc123-bash-5.2 /nix/store/xyz789-bash-5.2
/nix/store/def456-coreutils-9.0 /nix/store/uvw012-coreutils-9.0
```

Each line contains the original store path and the patched store path, space-separated.

---

## Building

### With Nix

```bash
# Build patchnar
nix build '.#patchnar'

# Test the binary
./result/bin/patchnar --help
```

### Dependencies

| Dependency | Purpose |
|------------|---------|
| autoconf, automake | Build system |
| pkg-config | Library detection |
| boost | Regex, shared_ptr (for source-highlight) |
| source-highlight | Shell script tokenization |

### Build Configuration

patchnar uses autoconf. The `configure.ac` detects source-highlight:

```m4
PKG_CHECK_MODULES([SOURCE_HIGHLIGHT], [source-highlight >= 3.0],
    [AC_DEFINE([HAVE_SOURCE_HIGHLIGHT], [1], ...)],
    [AC_MSG_WARN([source-highlight not found - string patching disabled])])
```

If source-highlight is not available, patchnar still works but without string-aware patching.

---

## Examples

### Basic Usage

```bash
# Patch a single package for Android
nix-store --dump /nix/store/xxx-package | patchnar \
  --prefix /data/data/com.termux.nix/files/usr \
  --glibc /nix/store/yyy-glibc-android-2.40 \
  --old-glibc /nix/store/zzz-glibc-2.40 \
| nix-store --restore /path/to/output
```

### With Hash Mappings

```bash
# Create mappings file
cat > mappings.txt << EOF
/nix/store/abc-dep1-1.0 /nix/store/xyz-dep1-1.0
/nix/store/def-dep2-2.0 /nix/store/uvw-dep2-2.0
EOF

# Patch with hash mappings
nix-store --dump /nix/store/xxx-package | patchnar \
  --prefix /data/data/com.termux.nix/files/usr \
  --glibc /nix/store/yyy-glibc-android-2.40 \
  --old-glibc /nix/store/zzz-glibc-2.40 \
  --mappings mappings.txt \
  --self-mapping "/nix/store/xxx-package /nix/store/patched-package" \
| nix-store --restore /path/to/output
```

### With String-Aware Patching

```bash
# Patch /nix/var/ paths in script strings
nix-store --dump /nix/store/xxx-nix-2.18 | patchnar \
  --prefix /data/data/com.termux.nix/files/usr \
  --glibc /nix/store/yyy-glibc-android-2.40 \
  --old-glibc /nix/store/zzz-glibc-2.40 \
  --add-prefix-to /nix/var/ \
  --source-highlight-data-dir /nix/store/src-highlite/share/source-highlight \
| nix-store --restore /path/to/output
```

### Debug Mode

```bash
# Enable debug output to see what's being patched
nix-store --dump /nix/store/xxx-package | patchnar \
  --prefix /data/data/com.termux.nix/files/usr \
  --debug \
  2>patchnar.log \
| nix-store --restore /path/to/output
```

---

## File Locations

```
submodules/patchnar/
├── configure.ac          # Autoconf configuration (source-highlight detection)
├── src/
│   ├── patchnar.cc       # Main patchnar source (NAR processing, string patching)
│   ├── nar.cc/nar.h      # NAR stream handling
│   ├── patchelf.cc       # ELF patching (from patchelf)
│   └── Makefile.am       # Build configuration
└── m4/                   # Autoconf macros

common/pkgs/
└── patchnar.nix          # Nix package definition

common/modules/android/
├── replace-android-dependencies.nix  # NixOS-style grafting
└── android-integration.nix           # replaceAndroidDependencies function
```

---

## References

- [patchelf](https://github.com/NixOS/patchelf) - Original ELF patcher
- [GNU Source-highlight](https://www.gnu.org/software/src-highlite/) - Syntax highlighting library
- [NAR format](https://nixos.org/manual/nix/stable/protocols/nix-archive.html) - Nix Archive specification
