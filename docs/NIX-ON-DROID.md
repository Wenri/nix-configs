# Nix-on-Droid Configuration Guide

> **Last Updated:** January 23, 2026
> **Platform:** Android/Termux (aarch64-linux)
> **Nix Version:** nixpkgs-unstable

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Installation](#installation)
4. [Configuration](#configuration)
5. [Package Management](#package-management)
6. [Services](#services)
7. [Home Manager Integration](#home-manager-integration)
8. [Troubleshooting](#troubleshooting)
9. [Related Documentation](#related-documentation)

---

## Overview

This repository provides a comprehensive nix-on-droid configuration that enables a full Nix development environment on Android devices. It's part of a unified infrastructure that shares configurations across 6 NixOS hosts + 1 nix-on-droid.

### Key Features

| Feature | Description |
|---------|-------------|
| **Android-patched glibc** | Custom glibc 2.40 with Termux patches for Android kernel compatibility |
| **NixOS-style grafting** | Recursive dependency patching with patchnar and hash mapping |
| **Binary cache support** | Packages from cache are patched at install time (no rebuilding) |
| **Home-manager integration** | Full home-manager support with shared modules from `common/` |
| **Unified infrastructure** | Same tools, packages, and configuration as desktop/server hosts |
| **Modular design** | Separate modules for SSH, locale, Shizuku, and Android integration |
| **SSH server** | Built-in SSHD with auto-start capability |
| **Shizuku integration** | Access to `rish` shell for privileged operations |

### What's Included

**System Packages:**
- Core Unix utilities (grep, sed, awk, find, etc.)
- Compression tools (gzip, bzip2, xz, zstd, p7zip)
- Network tools (curl, wget, openssh, rsync, aria2)
- System tools (htop, lsof, patchelf, gnupg)
- Editors (neovim)
- Modern CLI (ripgrep, fd, bat, eza, fzf, yq)
- Development (jq, make, gcc, binutils)

**Shell Environment:**
- Zsh with Oh-My-Zsh
- FZF integration
- Syntax highlighting
- History search
- Custom aliases for nix-on-droid

---

## Architecture

### How It Works

nix-on-droid uses a **two-stage approach** to run Nix packages on Android:

```
┌─────────────────────────────────────────────────────────────────┐
│              Stage 1: Build-time (NixOS-style grafting)          │
├─────────────────────────────────────────────────────────────────┤
│  replaceAndroidDependencies + patchnar:                          │
│  • IFD discovers full dependency closure                         │
│  • patchnar patches NAR streams (ELF, symlinks, scripts)         │
│  • Hash mapping substitutes inter-package references             │
│  • Result: All binaries use Android glibc + prefixed paths       │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Stage 2: Runtime                              │
├─────────────────────────────────────────────────────────────────┤
│                        Application                               │
│                            │                                     │
│                            ▼                                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  libfakechroot.so (LD_PRELOAD via ld.so.preload)          │  │
│  │  • Path translation: /nix/store → /data/.../nix/store     │  │
│  │  • Chroot virtualization                                   │  │
│  │  See: FAKECHROOT.md                                        │  │
│  └───────────────────────────────────────────────────────────┘  │
│                            │                                     │
│                            ▼                                     │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  Android glibc (with Termux patches)                       │  │
│  │  • Workarounds for blocked syscalls (clone3, rseq, etc.)  │  │
│  │  See: ANDROID-GLIBC.md                                     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                            │                                     │
│                            ▼                                     │
│                    Android Kernel (seccomp)                      │
└─────────────────────────────────────────────────────────────────┘
```

**Key insight:** Most packages come from the Nix binary cache. patchnar patches them at install time using NAR stream processing - no package rebuilding needed!

**NixOS-style grafting:** The `build.replaceAndroidDependencies` function implements recursive dependency patching similar to nixpkgs' `replaceDependencies`. It uses IFD with `exportReferencesGraph` to discover the full closure, then patches each package with patchnar. Hash mapping ensures all inter-package store path references are updated consistently.

### Flake Structure

```
flake.nix
├── nixOnDroidConfigurations
│   ├── default                    # Standard nix-on-droid config
│   └── nix-on-droid              # Named config
├── packages.aarch64-linux
│   ├── androidGlibc              # Android-patched glibc 2.40
│   └── androidFakechroot         # Android-patched fakechroot
└── lib.aarch64-linux
    └── androidGlibc              # Exported glibc package
```

### Module Structure

```
common/modules/android/
├── default.nix                       # Module exports
├── base.nix                          # Core configuration (packages, nix settings)
├── android-integration.nix           # NixOS-style grafting with patchnar, Termux tools
├── replace-android-dependencies.nix  # IFD-based recursive dependency patching
├── sshd.nix                          # SSH server configuration
├── locale.nix                        # Locale and timezone
└── shizuku.nix                       # Shizuku rish shell integration

hosts/nix-on-droid/
├── configuration.nix             # System configuration
└── home.nix                      # Home-manager configuration

submodules/
├── fakechroot/                   # Android-patched fakechroot source
├── glibc/                        # Pre-patched glibc source (release/2.40)
├── patchnar/                     # NAR stream patcher (ELF, symlinks, scripts)
├── nix-on-droid/                 # nix-on-droid source (fork)
└── secrets/                      # Secrets repository
```

---

## Installation

### Prerequisites

1. **Android device** with Android 7.0+ (API 24+)
2. **Termux** installed from F-Droid (not Google Play)
3. **Storage permission** granted to Termux
4. **~5GB free storage** for Nix store

### Step 1: Install Nix-on-Droid

```bash
# Option A: Install from F-Droid
# Search "Nix-on-Droid" and install

# Option B: Install from GitHub releases
# Download APK from: https://github.com/nix-community/nix-on-droid/releases
```

### Step 2: Initial Setup

Launch Nix-on-Droid and wait for initial bootstrap (~2-5 minutes).

### Step 3: Clone Configuration

```bash
# Install git if not available
nix-shell -p git

# Clone repository with submodules
git clone --recurse-submodules https://github.com/Wenri/nix-configs ~/.config/nix-on-droid
cd ~/.config/nix-on-droid

# Or if already cloned, initialize submodules:
git submodule update --init --recursive
```

### Step 4: Apply Configuration

```bash
# First-time build (may take 20+ minutes for glibc)
nix-on-droid switch --flake ~/.config/nix-on-droid

# Or from within the directory
cd ~/.config/nix-on-droid
nix-on-droid switch --flake .
```

### Step 5: Restart Shell

```bash
exec zsh
```

---

## Configuration

### System Configuration

The system configuration is in `hosts/nix-on-droid/configuration.nix`:

```nix
{ config, lib, pkgs, inputs, outputs, hostname, username, ... }: {
  imports = [
    outputs.nixOnDroidModules.base              # Core packages and nix settings
    outputs.nixOnDroidModules.android-integration  # Termux tools
    outputs.nixOnDroidModules.sshd              # SSH server
    outputs.nixOnDroidModules.locale            # Timezone and locale
    outputs.nixOnDroidModules.shizuku           # Shizuku rish shell
  ];

  # Enable Android/Termux integration tools
  android.termuxTools = true;

  # Enable SSH server
  services.sshd.enable = true;

  # Enable Shizuku rish shell
  programs.shizuku.enable = true;

  # Configure home-manager
  home-manager = {
    config = ./home.nix;
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
    extraSpecialArgs = config._module.specialArgs;
  };
}
```

### Home Manager Configuration

The home-manager configuration is in `hosts/nix-on-droid/home.nix`:

```nix
{ lib, pkgs, outputs, hostname, username, ... }: let
  keys = import ../../common/keys.nix;
in {
  imports = [
    outputs.homeModules.core.default  # Shared core modules (git, zsh, ssh, gh)
  ];

  home.stateVersion = "24.05";

  # SSH authorized keys
  home.file.".ssh/authorized_keys".text = lib.concatStringsSep "\n" keys.all;

  # nix-on-droid specific aliases
  programs.zsh.shellAliases = {
    update = "nix-on-droid switch --flake ~/.config/nix-on-droid";
    sshd-start = "~/.termux/boot/start-sshd";
    sshd-stop = "pkill -f 'sshd -f'";
  };
}
```

---

## Package Management

### Updating Configuration

```bash
# Pull latest changes
cd ~/.config/nix-on-droid
git pull

# Update flake inputs
nix flake update

# Apply changes
nix-on-droid switch --flake .
```

### Adding Packages

**Option 1: Edit common/packages.nix** (affects all hosts)
```nix
devTools = with pkgs; [
  jq
  gnumake
  python3  # Add here
];
```

**Option 2: Edit hosts/nix-on-droid/configuration.nix** (nix-on-droid only)
```nix
environment.packages = [
  pkgs.python3
];
```

**Option 3: Temporary shell**
```bash
nix-shell -p python3 nodejs
```

### Garbage Collection

```bash
# Remove old generations
nix-on-droid rollback  # If needed first
nix-collect-garbage -d

# Check store size
du -sh /nix/store
```

---

## Services

### SSH Server

The SSH server is configured via `common/modules/nix-on-droid/sshd.nix`:

```nix
{
  services.sshd = {
    enable = true;
    port = 8022;  # Default port (1024+ doesn't need root)
  };
}
```

**Usage:**
```bash
# Start SSH server
sshd-start

# Stop SSH server
sshd-stop

# Connect from another device
ssh -p 8022 user@device-ip
```

### Shizuku Integration

[Shizuku](https://shizuku.rikka.app/) provides a way to run commands with ADB permissions:

```bash
# Start Shizuku app first, then:
rish

# Run commands with elevated permissions
rish -c "pm list packages"
```

### Termux Integration

Android environment variables and Termux tools are handled by `android-integration.nix`:
- Provides access to `termux-*` commands
- Sets up Android environment variables
- Handles clipboard integration

---

## Home Manager Integration

### Shared Modules

| Module | Path | Description |
|--------|------|-------------|
| `core.default` | `common/home-manager/core/default.nix` | CLI essentials + git/zsh/ssh/gh |
| `core.git` | `common/home-manager/core/git.nix` | Git config with 1Password signing |
| `core.zsh` | `common/home-manager/core/zsh.nix` | Zsh with oh-my-zsh |
| `core.ssh` | `common/home-manager/core/ssh.nix` | SSH with 1Password agent |
| `core.gh` | `common/home-manager/core/gh.nix` | GitHub CLI |

### Module Import Pattern

```nix
# In hosts/nix-on-droid/home.nix
{ outputs, ... }: {
  imports = [
    outputs.homeModules.core.default  # Imports all core modules
  ];
}
```

### Android-Specific Home Manager Settings

The nix-on-droid home configuration includes Android-specific settings:

**Session Variables:**
```nix
home.sessionVariables = {
  CLAUDE_CODE_TMPDIR = "${androidPaths.installationDir}/tmp";
};
```

**Additional PATH:**
```nix
home.sessionPath = ["$HOME/.local/bin"];
```

**Default umask (for shared storage compatibility):**
```nix
programs.zsh.envExtra = ''
  umask 002
  # Also source Termux environment variables...
'';
```

**Git safe.directory (for shared storage):**
```nix
programs.git.extraConfig = {
  safe.directory = "/storage/emulated/*";
};
```

These settings ensure:
- `CLAUDE_CODE_TMPDIR`: Claude Code uses a temp directory within the Android prefix
- `~/.local/bin` in PATH: User-installed binaries are accessible
- `umask 002`: Files created in shared storage have group write permission
- `safe.directory`: Git can work with repositories in Android shared storage (owned by a different UID)

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| "Bad system call" | Android glibc not being used - check ld.so.preload |
| Build fails "out of space" | Run `nix-collect-garbage -d` |
| SSH connection refused | Check `pgrep -f sshd`, verify port 8022 |
| malloc corruption | Update fakechroot from submodule |
| "nix-env: command not found" in activation | Activation packages not patched - check `build.replaceAndroidDependencies` |
| "__build-remote: error loading shared libraries" | See build-hook fix below |
| Package conflict (strip) | Remove duplicate binutils if gcc-wrapper is present |
| Node.js can't find modules | See Node.js direct syscalls fix below |

### Build-Hook Error Fix

If you see this error during `nix-on-droid switch`:
```
__build-remote: error while loading shared libraries: __build-remote: cannot open shared object file
```

**Cause:** Nix dynamically determines its `build-hook` based on the interpreter (ld.so). On Android, it incorrectly generates:
```
build-hook = /nix/store/.../glibc-android.../ld-linux-aarch64.so.1 __build-remote
```

This fails because `__build-remote` is a nix subcommand, not a standalone program. When ld.so is invoked directly, it tries to load `__build-remote` as a shared library.

**Fix:** Add to `nix.extraOptions` in your configuration:
```nix
nix.extraOptions = ''
  experimental-features = nix-command flakes
  build-hook =
  builders =
  pure-eval = false
  build-dir = ${androidPaths.installationDir}/nix/var/nix/builds
'';
```

**Note:** The `build-dir` setting is important for Android. It sets the directory where Nix performs builds. Using a path within the Android app directory (`$PREFIX/nix/var/nix/builds`) ensures builds work properly within the Android sandbox.

**Workaround for current build:** If the config change isn't applied yet, use:
```bash
nix-on-droid switch --flake . --option build-hook "" --option builders ""
```

### Node.js Direct Syscalls Fix

Node.js (and npm) make direct syscalls that bypass fakechroot's LD_PRELOAD path translation. This causes issues with packages like `claude-code` that rely on Node.js finding files in `/nix/store`.

**Symptom:** Node.js-based tools fail with "module not found" or similar errors because they can't find files at the `/nix/store` path.

**Solution:** The overlay in `common/overlays/default.nix` uses `symlinkJoin` to wrap affected packages and substitute `/nix/store` paths with the real Android filesystem path:

```nix
claude-code = if installationDir != null then
  final.symlinkJoin {
    name = "claude-code-${prev.claude-code.version}";
    paths = [ prev.claude-code ];
    postBuild = ''
      rm $out/bin/claude $out/bin/.claude-wrapped
      substitute ${prev.claude-code}/bin/.claude-wrapped $out/bin/.claude-wrapped \
        --replace "${prev.claude-code}/lib" "${installationDir}${prev.claude-code}/lib"
      # ...
    '';
  }
else prev.claude-code;
```

**Key points:**
- Uses `symlinkJoin` instead of `overrideAttrs` to avoid triggering npm rebuild (which also fails due to syscall issues)
- Only applies when `installationDir` is set (Android builds only)
- Substitutes paths in wrapper scripts, not the original package

**To add support for another Node.js package**, follow the same pattern in `common/overlays/default.nix`.

### Debugging Commands

```bash
# Check current generation
nix-on-droid list-generations

# Rollback to previous generation
nix-on-droid rollback

# Build without switching
nix-on-droid build --flake .

# Show build trace
nix-on-droid switch --flake . --show-trace

# Check flake
nix flake check
nix flake show
```

### Debug Hook

For login issues, edit `~/.config/nix-on-droid/login-debug.sh`:

```bash
#!/system/bin/sh
# Sourced at the beginning of /bin/login

# Enable verbose output
export FAKECHROOT_DEBUG=1

echo "DEBUG: login starting" >&2
```

Changes take effect on next login.

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [ANDROID-GLIBC.md](./ANDROID-GLIBC.md) | Android glibc patches, build process, ld.so path translation |
| [FAKECHROOT.md](./FAKECHROOT.md) | libfakechroot modifications, integration with glibc |
| [../CLAUDE.md](../CLAUDE.md) | Repository overview for AI assistants |

### External Resources

- [nix-on-droid GitHub](https://github.com/nix-community/nix-on-droid)
- [nix-on-droid Wiki](https://github.com/nix-community/nix-on-droid/wiki)
- [Termux Wiki](https://wiki.termux.com/)
- [Shizuku Documentation](https://shizuku.rikka.app/guide/setup/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
