# Nix-on-Droid Configuration Guide

> **Last Updated:** December 2024
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
9. [Advanced Topics](#advanced-topics)
10. [Related Documentation](#related-documentation)

---

## Overview

This repository provides a comprehensive nix-on-droid configuration that enables a full Nix development environment on Android devices. It's part of a unified infrastructure that shares configurations across 6 NixOS hosts + 1 nix-on-droid.

### Key Features

| Feature | Description |
|---------|-------------|
| **Android-patched glibc** | Custom glibc 2.40 with Termux patches for Android kernel compatibility |
| **Binary cache support** | Uses patchelf to rewrite binaries instead of rebuilding everything |
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

### Flake Structure

```
flake.nix
├── nixOnDroidConfigurations
│   ├── default                    # Standard nix-on-droid config
│   └── nix-on-droid              # Named config
├── packages.aarch64-linux
│   └── androidGlibc              # Android-patched glibc 2.40
└── lib.aarch64-linux
    ├── androidGlibc              # Exported glibc package
    └── patchPackageForAndroidGlibc  # Function to patch any package
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
```

### Configuration Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                         flake.nix                               │
│  mkNixOnDroidConfiguration { hostname, system, username }       │
│                              │                                  │
│  ┌───────────────────────────┼───────────────────────────────┐ │
│  │                           ▼                               │ │
│  │  hosts/nix-on-droid/configuration.nix                    │ │
│  │    imports:                                               │ │
│  │      - outputs.nixOnDroidModules.base                    │ │
│  │      - outputs.nixOnDroidModules.android-integration     │ │
│  │      - outputs.nixOnDroidModules.sshd                    │ │
│  │      - outputs.nixOnDroidModules.locale                  │ │
│  │      - outputs.nixOnDroidModules.shizuku                 │ │
│  │                           │                               │ │
│  │                           ▼                               │ │
│  │  home-manager.config = ./home.nix                        │ │
│  │    imports:                                               │ │
│  │      - outputs.homeModules.core.default                  │ │
│  └───────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
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

# Clone repository
git clone https://github.com/Wenri/nix-configs ~/.config/nix-on-droid
cd ~/.config/nix-on-droid
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
# Log out and back in, or:
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

### Package Lists

Packages are defined in `common/packages.nix` and imported by modules:

```nix
{ pkgs }: {
  coreUtils = with pkgs; [ procps killall diffutils findutils ... ];
  compression = with pkgs; [ bzip2 gzip xz zip unzip zstd p7zip ];
  networkTools = with pkgs; [ curl wget openssh iproute2 ... ];
  systemTools = with pkgs; [ glibc.bin hostname man htop lsof ... ];
  editors = with pkgs; [ neovim ];
  modernCli = with pkgs; [ ripgrep fd bat eza fzf yq ];
  devTools = with pkgs; [ jq gnumake binutils gcc ];
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

# Auto-start on boot (via Termux:Boot)
# Requires ~/.termux/boot/start-sshd script
```

### Shizuku Integration

[Shizuku](https://shizuku.rikka.app/) provides a way to run commands with ADB permissions. The `rish` shell is configured via `common/modules/nix-on-droid/shizuku.nix`:

```nix
{
  programs.shizuku = {
    enable = true;
    # Provides 'rish' command when Shizuku is running
  };
}
```

**Usage:**
```bash
# Start Shizuku app first, then:
rish

# Run commands with elevated permissions
rish -c "pm list packages"
```

### Termux Integration

Android environment variables and Termux tools are handled by `common/modules/nix-on-droid/android-integration.nix`:

- Provides access to `termux-*` commands
- Sets up Android environment variables
- Handles clipboard integration

---

## Home Manager Integration

### Shared Modules

The nix-on-droid configuration imports shared home-manager modules:

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
  
  # Or import individual modules:
  # imports = [
  #   outputs.homeModules.core.git
  #   outputs.homeModules.core.zsh
  # ];
}
```

### Adding Desktop Modules

Desktop modules are NOT imported by default (no GUI on Android), but you can import specific ones if needed:

```nix
{ outputs, ... }: {
  imports = [
    outputs.homeModules.core.default
    # outputs.homeModules.desktop.emacs  # If you want Emacs config
  ];
}
```

---

## Troubleshooting

### Common Issues

#### "Bad system call" Error

**Symptom:**
```bash
$ ./some-binary
Bad system call (core dumped)
```

**Cause:** Binary uses syscalls blocked by Android seccomp

**Solutions:**
1. Most packages work under proot (default nix-on-droid environment)
2. For specific packages, use `patchPackageForAndroidGlibc`:
   ```nix
   { patchPackageForAndroidGlibc, pkgs, ... }: {
     environment.packages = [
       (patchPackageForAndroidGlibc pkgs.problematic-package)
     ];
   }
   ```

#### Build Fails with "out of space"

**Symptom:** Build fails with disk space errors

**Solutions:**
```bash
# Free up space
nix-collect-garbage -d

# Check available space
df -h /data

# Move Nix store (advanced)
# See: https://github.com/nix-community/nix-on-droid/wiki/FAQ
```

#### Home-manager Activation Errors

**Symptom:** `error: collision between ... and ...`

**Solutions:**
```bash
# Check for conflicting files
ls -la ~/.config/

# Remove old backups
find ~ -name "*.hm-bak" -delete

# Force rebuild
nix-on-droid switch --flake . --recreate-lock-file
```

#### SSH Connection Refused

**Symptom:** Can't connect via SSH

**Checklist:**
1. Is SSH server running? `pgrep -f sshd`
2. Is the port correct? Default is 8022
3. Is the device on the same network?
4. Are authorized_keys correct? Check `~/.ssh/authorized_keys`

```bash
# Manually start SSH
sshd-start

# Check listening ports
netstat -tlnp | grep 8022
```

#### Android Environment Variables Missing

**Symptom:** `$ANDROID_ROOT` or `$TERMUX_*` not set in SSH sessions

**Solution:** This is handled by `envExtra` in home.nix:
```nix
programs.zsh.envExtra = ''
  if [ -z "$ANDROID_ROOT" ] && [ -f "/.../termux.env" ]; then
    eval "$(grep -v -E '^export (PATH|HOME|...)=' "/.../termux.env")"
  fi
'';
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

---

## Advanced Topics

### Android glibc Patching

See [GLIBC_REPLACEMENT.md](./GLIBC_REPLACEMENT.md) for detailed information on:
- How the Android glibc patches work
- Using `patchPackageForAndroidGlibc`
- Building custom patched packages

### Custom Packages

Add packages to `common/pkgs/`:

```bash
mkdir -p common/pkgs/my-package
cat > common/pkgs/my-package/default.nix << 'EOF'
{ pkgs }: pkgs.stdenv.mkDerivation {
  pname = "my-package";
  version = "1.0";
  # ...
}
EOF
```

Then use: `nix build .#my-package`

### Multiple Configurations

You can have multiple nix-on-droid configurations:

```nix
# In flake.nix
nixOnDroidConfigurations = {
  default = mkNixOnDroidConfiguration { ... };
  minimal = mkNixOnDroidConfiguration { ... };  # Add another
};
```

Switch between them:
```bash
nix-on-droid switch --flake .#minimal
```

### Termux:Boot Auto-Start

To start services on device boot:

1. Install Termux:Boot from F-Droid
2. Create `~/.termux/boot/` directory
3. Add executable scripts

The SSH auto-start script is created by the `sshd` module.

### Cross-Compilation

Building for aarch64-linux on x86_64:

```bash
# On x86_64 system with binfmt configured
nix build .#androidGlibc --system aarch64-linux
```

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [GLIBC_REPLACEMENT.md](./GLIBC_REPLACEMENT.md) | Android glibc technical details |
| [TERMUX-PATCHES.md](./TERMUX-PATCHES.md) | Termux patch documentation |
| [../CLAUDE.md](../CLAUDE.md) | Repository overview for AI assistants |
| [../README.md](../README.md) | Main project README |

### External Resources

- [nix-on-droid GitHub](https://github.com/nix-community/nix-on-droid)
- [nix-on-droid Wiki](https://github.com/nix-community/nix-on-droid/wiki)
- [Termux Wiki](https://wiki.termux.com/)
- [Shizuku Documentation](https://shizuku.rikka.app/guide/setup/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
