# Nix-on-Droid Configuration Guide

> **Last Updated:** December 28, 2025
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
| **Binary cache support** | ld.so built-in path translation instead of rebuilding packages |
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

nix-on-droid uses a **layered approach** to run Nix packages on Android:

```
┌─────────────────────────────────────────────────────────────────┐
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
│  │  Android glibc (ld.so with built-in features)              │  │
│  │  • Termux patches for blocked syscalls                     │  │
│  │  • RPATH translation in decompose_rpath()                  │  │
│  │  • Standard glibc → Android glibc redirection              │  │
│  │  See: ANDROID-GLIBC.md                                     │  │
│  └───────────────────────────────────────────────────────────┘  │
│                            │                                     │
│                            ▼                                     │
│                    Android Kernel (seccomp)                      │
└─────────────────────────────────────────────────────────────────┘
```

**Key insight:** Most packages come from the Nix binary cache unchanged. The Android glibc's ld.so automatically redirects library paths at runtime, so no patchelf or rebuilding is needed!

**Environment patching:** The `build.replaceAndroidDependencies` function patches the entire `environment.path` (a buildEnv of all packages) for Android glibc compatibility. This includes activation script tools (bash, coreutils, nix, etc.) which run outside the fakechroot environment.

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
common/modules/nix-on-droid/
├── default.nix                   # Module exports
├── base.nix                      # Core configuration (packages, nix settings)
├── android-integration.nix       # Termux tools integration
├── sshd.nix                      # SSH server configuration
├── locale.nix                    # Locale and timezone
└── shizuku.nix                   # Shizuku rish shell integration

hosts/nix-on-droid/
├── configuration.nix             # System configuration
└── home.nix                      # Home-manager configuration

submodules/
├── fakechroot/                   # Android-patched fakechroot source
├── glibc/                        # Pre-patched glibc source (release/2.40)
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
  build-hook =
  builders =
'';
```

**Workaround for current build:** If the config change isn't applied yet, use:
```bash
nix-on-droid switch --flake . --option build-hook "" --option builders ""
```

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
