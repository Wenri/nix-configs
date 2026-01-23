# patchnar: NAR Stream Patcher

> **Last Updated:** January 23, 2026
> **Version:** 0.22.0
> **Based on:** patchelf

## Table of Contents

1. [Overview](#overview)
2. [How It Works](#how-it-works)
3. [Parallel Processing Architecture](#parallel-processing-architecture)
4. [Command-Line Options](#command-line-options)
5. [String-Aware Patching](#string-aware-patching)
6. [Integration with NixOS-style Grafting](#integration-with-nixos-style-grafting)
7. [Building](#building)
8. [Examples](#examples)

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

## Parallel Processing Architecture

patchnar uses a three-phase batch processing architecture for efficient parallel patching:

### Three-Phase Pipeline

```
┌─────────────────────────────────────────────────────────────────┐
│ Phase 1: PARSE                                                   │
│ - Read entire NAR stream into in-memory tree (NarNode)          │
│ - Tree structure: NarRegular, NarSymlink, NarDirectory          │
│ - Single-threaded (NAR is a sequential format)                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 2: PATCH (parallel)                                        │
│ - Collect all regular files into PatchTask vector               │
│ - Execute all patches in parallel via std::execution::par       │
│ - Each PatchTask is self-contained with file ref, path, patcher │
│ - Thread count controlled by TBB_NUM_THREADS environment var    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│ Phase 3: WRITE                                                   │
│ - Serialize patched tree back to NAR format                     │
│ - Single-threaded (NAR requires sequential output)              │
│ - Directory entries written in lexicographic order              │
└─────────────────────────────────────────────────────────────────┘
```

### PatchTask Design

Each file to be patched is represented by a self-contained `PatchTask`:

```cpp
struct PatchTask {
    NarRegular& file;              // Reference to file in tree
    const std::string path;        // File path within NAR
    const ContentPatcher& patcher; // Reference to content patcher function
    void operator()() {
        file.content = patcher(file.content, file.executable, path);
    }
};
```

Tasks are executed in parallel using:

```cpp
std::for_each(std::execution::par, tasks.begin(), tasks.end(),
    std::mem_fn(&PatchTask::operator()));
```

### Thread Control

Thread count is controlled by the **TBB_NUM_THREADS** environment variable (Intel TBB runtime):

```bash
# Use 4 threads
TBB_NUM_THREADS=4 patchnar --prefix /data/... < input.nar > output.nar

# Use all available cores (default)
patchnar --prefix /data/... < input.nar > output.nar
```

### Why Batch Processing?

| Approach | Pros | Cons |
|----------|------|------|
| **Streaming** | Low memory | No parallelism (NAR is sequential) |
| **Batch (current)** | Full parallelism | Memory for entire tree |

Since source-highlight tokenization is the expensive part, parallel patching provides significant speedup for packages with many source files.

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
- JSON (`.json`) - all string values are patched (no comments in JSON)
- Makefiles (`Makefile`, `makefile`)
- And many more...

### Patching Decision Logic

For each path pattern specified with `--add-prefix-to`, patchnar decides whether to patch based on this decision tree:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Can the file's language be detected from filename?           │
│    (Uses LangMap: extension → .lang file)                       │
│                                                                 │
│    NO  ──────────────────────────────────────────→ NOT PATCHED  │
│    YES ↓                                                        │
├─────────────────────────────────────────────────────────────────┤
│ 2. Is the path inside a "string" token region?                  │
│    (Source-highlight tokenizes and marks string literals)       │
│                                                                 │
│    NO  ──────────────────────────────────────────→ NOT PATCHED  │
│    YES ↓                                                        │
├─────────────────────────────────────────────────────────────────┤
│ 3. Is the path already prefixed?                                │
│    (Checks if prefix immediately precedes the path)             │
│                                                                 │
│    YES ─────────────────────────────────────────→ NOT PATCHED   │
│    NO  ↓                                                        │
├─────────────────────────────────────────────────────────────────┤
│                        ✓ PATCHED                                │
│    Prefix is inserted before the path pattern                   │
└─────────────────────────────────────────────────────────────────┘
```

### What Counts as a "String Token"

Source-highlight's language definitions (`.lang` files) define what constitutes a string in each language. The `"string"` token type typically includes:

| Language | String Delimiters Recognized |
|----------|------------------------------|
| Shell | `"..."`, `'...'`, `$'...'` |
| Python | `"..."`, `'...'`, `"""..."""`, `'''...'''` |
| C/C++ | `"..."` |
| JavaScript | `"..."`, `'...'`, `` `...` `` (template literals) |
| JSON | `"..."` (all values are strings, no comments) |
| Perl | `"..."`, `'...'`, `q{...}`, `qq{...}` |
| Ruby | `"..."`, `'...'`, `%q{...}`, `%Q{...}` |

---

### Examples: What Gets PATCHED ✓

#### 1. Double-Quoted Strings (Shell)
```bash
export PATH="/nix/var/nix/profiles/default/bin:$PATH"
#            ↑ PATCHED (inside double quotes)
```

#### 2. Single-Quoted Strings (Shell)
```bash
echo '/nix/var/nix/profiles/default'
#     ↑ PATCHED (inside single quotes)
```

#### 3. Assignment with Quotes (Shell)
```bash
NIX_PATH="/nix/var/nix/profiles/default"
#         ↑ PATCHED (inside double quotes)
```

#### 4. Python String Literals
```python
config_path = "/nix/var/nix/profiles/default"
#              ↑ PATCHED (inside double quotes)

other_path = '/nix/var/other/path'
#             ↑ PATCHED (inside single quotes)
```

#### 5. Python Triple-Quoted Strings
```python
doc = """
The default profile is at /nix/var/nix/profiles/default
"""                       # ↑ PATCHED (inside triple quotes)
```

#### 6. C/C++ String Literals
```c
const char* path = "/nix/var/nix/profiles/default";
//                  ↑ PATCHED (inside double quotes)
```

#### 7. JavaScript Strings
```javascript
const nixPath = "/nix/var/nix/profiles/default";
//               ↑ PATCHED (inside double quotes)

const other = '/nix/var/other';
//             ↑ PATCHED (inside single quotes)
```

#### 8. Perl Strings
```perl
my $path = "/nix/var/nix/profiles/default";
#           ↑ PATCHED (inside double quotes)

my $other = qq{/nix/var/other/path};
#              ↑ PATCHED (inside qq{})
```

#### 9. JSON String Values
```json
{
  "nixProfile": "/nix/var/nix/profiles/default",
                 ↑ PATCHED (JSON string value)
  "nested": {
    "path": "/nix/var/nix/profiles/per-user/root"
             ↑ PATCHED (nested string value)
  }
}
```

> **Note:** JSON has no comment syntax (officially), so ALL string values containing the pattern will be patched. This is usually the desired behavior for configuration files.

---

### Examples: What Does NOT Get Patched ✗

#### 1. Comments (Any Language)
```bash
# This path /nix/var/nix/profiles/default is in a comment
#            ↑ NOT PATCHED (comment, not string)
```

```python
# Config at /nix/var/nix/profiles/default
#            ↑ NOT PATCHED (comment)
```

```c
// Path: /nix/var/nix/profiles/default
//        ↑ NOT PATCHED (comment)

/* /nix/var/nix/profiles/default */
#   ↑ NOT PATCHED (block comment)
```

#### 2. Variable Expansions (Would Cause Double-Prefix)
```bash
echo $PREFIX/nix/var/nix/profiles/default
#            ↑ NOT PATCHED (follows variable, would become $PREFIX/$PREFIX/nix/var/...)

echo "${NIX_ROOT}/nix/var/path"
#                 ↑ NOT PATCHED (follows variable inside string)
```

#### 3. Bare Paths Without Quotes (Shell)
```bash
ls /nix/var/nix/profiles/default
#   ↑ NOT PATCHED (not inside quotes - shell argument, not string literal)

cat /nix/var/nix/profiles/default/etc/profile
#    ↑ NOT PATCHED (bare path)
```

#### 4. Already Prefixed Paths
```bash
PATH="/data/data/com.termux.nix/files/usr/nix/var/nix/profiles/default"
#                                          ↑ NOT PATCHED (already has prefix)
```

#### 5. Unrecognized File Types
```
# File: config.xyz (no .lang file for .xyz extension)
path = "/nix/var/nix/profiles/default"
#       ↑ NOT PATCHED (language not detected)
```

#### 6. Binary Files
Binary files are not processed for string patching (only ELF patching for interpreter/RPATH).

#### 7. Here-Documents Without Quotes (Shell)
```bash
cat << EOF
/nix/var/nix/profiles/default
EOF
# ↑ NOT PATCHED (heredoc content is not tokenized as "string")

cat << 'EOF'
/nix/var/nix/profiles/default
EOF
# ↑ NOT PATCHED (quoted heredoc, but still not a string token)
```

#### 8. Code Outside Strings
```python
import nix_var_module  # "nix_var" in identifier
#      ↑ NOT PATCHED (not a string, just happens to contain pattern)

path = nix_var_path    # variable name
#      ↑ NOT PATCHED (identifier, not string)
```

```c
#define NIX_VAR_PATH /nix/var
//                    ↑ NOT PATCHED (macro, not string literal)
```

---

### Complete Example: Shell Script

**Input (`nix.sh`):**
```bash
#!/bin/sh
# Configuration for Nix
# Default profile: /nix/var/nix/profiles/default

export NIX_PROFILES="/nix/var/nix/profiles/default $HOME/.nix-profile"
export XDG_DATA_DIRS="/nix/var/nix/profiles/default/share:$XDG_DATA_DIRS"

# Don't patch this comment: /nix/var/should/stay
echo "Using profile at /nix/var/nix/profiles/default"

# Variable expansion - already prefixed conceptually
echo $PREFIX/nix/var/should/not/patch

# Bare path (not in quotes)
ls /nix/var/nix/profiles/default/bin

# Single quotes
STATIC_PATH='/nix/var/nix/profiles/default/lib'
```

**Output (after `--add-prefix-to /nix/var/`):**
```bash
#!/bin/sh
# Configuration for Nix
# Default profile: /nix/var/nix/profiles/default                    ← NOT PATCHED (comment)

export NIX_PROFILES="/data/.../nix/var/nix/profiles/default $HOME/.nix-profile"
#                    ↑ PATCHED
export XDG_DATA_DIRS="/data/.../nix/var/nix/profiles/default/share:$XDG_DATA_DIRS"
#                     ↑ PATCHED

# Don't patch this comment: /nix/var/should/stay                    ← NOT PATCHED (comment)
echo "Using profile at /data/.../nix/var/nix/profiles/default"
#                       ↑ PATCHED

# Variable expansion - already prefixed conceptually
echo $PREFIX/nix/var/should/not/patch                               ← NOT PATCHED (after $PREFIX)

# Bare path (not in quotes)
ls /nix/var/nix/profiles/default/bin                                ← NOT PATCHED (bare path)

# Single quotes
STATIC_PATH='/data/.../nix/var/nix/profiles/default/lib'
#            ↑ PATCHED
```

---

### Complete Example: Python Script

**Input (`config.py`):**
```python
#!/usr/bin/env python3
"""
Nix configuration module.
Default path: /nix/var/nix/profiles/default
"""

# System paths - don't modify comments
# /nix/var/nix/profiles/default is the default

NIX_PROFILE = "/nix/var/nix/profiles/default"
ALT_PROFILE = '/nix/var/nix/profiles/per-user/root'

def get_path():
    # Return /nix/var/nix/profiles/default
    return "/nix/var/nix/profiles/default"

# f-string with variable
prefix = os.environ.get("PREFIX", "")
full_path = f"{prefix}/nix/var/nix/profiles/default"
```

**Output (after `--add-prefix-to /nix/var/`):**
```python
#!/usr/bin/env python3
"""
Nix configuration module.
Default path: /data/.../nix/var/nix/profiles/default               ← PATCHED (docstring)
"""

# System paths - don't modify comments
# /nix/var/nix/profiles/default is the default                      ← NOT PATCHED (comment)

NIX_PROFILE = "/data/.../nix/var/nix/profiles/default"
#              ↑ PATCHED
ALT_PROFILE = '/data/.../nix/var/nix/profiles/per-user/root'
#              ↑ PATCHED

def get_path():
    # Return /nix/var/nix/profiles/default                          ← NOT PATCHED (comment)
    return "/data/.../nix/var/nix/profiles/default"
#           ↑ PATCHED

# f-string with variable
prefix = os.environ.get("PREFIX", "")
full_path = f"{prefix}/nix/var/nix/profiles/default"
#                      ↑ NOT PATCHED (follows variable in f-string)
```

---

### Complete Example: JSON Configuration

**Input (`config.json`):**
```json
{
  "name": "nix-config",
  "version": "1.0.0",
  "paths": {
    "nixProfile": "/nix/var/nix/profiles/default",
    "nixStore": "/nix/store",
    "customPath": "/nix/var/custom/path"
  },
  "description": "Path /nix/var/nix/profiles/default is used",
  "nested": {
    "deep": {
      "path": "/nix/var/nix/profiles/per-user/root"
    }
  }
}
```

**Output (after `--add-prefix-to /nix/var/`):**
```json
{
  "name": "nix-config",
  "version": "1.0.0",
  "paths": {
    "nixProfile": "/data/.../nix/var/nix/profiles/default",
    ↑ PATCHED
    "nixStore": "/nix/store",
    ↑ NOT PATCHED (pattern is /nix/var/, not /nix/store/)
    "customPath": "/data/.../nix/var/custom/path"
    ↑ PATCHED
  },
  "description": "Path /data/.../nix/var/nix/profiles/default is used",
  ↑ PATCHED (all JSON strings are string literals)
  "nested": {
    "deep": {
      "path": "/data/.../nix/var/nix/profiles/per-user/root"
      ↑ PATCHED
    }
  }
}
```

> **Note:** In JSON, ALL string values are treated as string literals (JSON has no comments), so every occurrence of the pattern in any string value will be patched.

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
