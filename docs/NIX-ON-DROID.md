# Nix-on-Droid Configuration

## Overview

This configuration provides a full Nix environment on Android via [nix-on-droid](https://github.com/nix-community/nix-on-droid).

## Key Features

- **Android-patched glibc**: Custom glibc 2.40 with Termux patches for Android compatibility
- **Binary cache support**: Uses patchelf to rewrite binaries instead of rebuilding
- **Home-manager integration**: Full home-manager support with shared modules
- **Unified infrastructure**: Same tools and configuration as desktop/server hosts

## Quick Start

### Installation

1. Install Nix-on-Droid from F-Droid or GitHub releases
2. Clone this repository:
   ```bash
   git clone https://github.com/Wenri/nix-configs ~/.config/nix-on-droid
   ```
3. Apply configuration:
   ```bash
   nix-on-droid switch --flake ~/.config/nix-on-droid
   ```

### Updating

```bash
cd ~/.config/nix-on-droid
git pull
nix flake update
nix-on-droid switch --flake .
```

## Architecture

### Flake Structure

```
flake.nix
├── nixOnDroidConfigurations.default  # Main nix-on-droid config
├── packages.aarch64-linux.androidGlibc  # Android-patched glibc
└── lib.aarch64-linux.patchPackageForAndroidGlibc  # Patch function
```

### Configuration Files

- `configuration.nix` - System-level nix-on-droid configuration
- `home.nix` - Home-manager configuration

### Android glibc Integration

All packages are automatically patched to use Android-compatible glibc:

```nix
{ patchPackageForAndroidGlibc, pkgs, ... }: {
  environment.packages = map patchPackageForAndroidGlibc [
    pkgs.git
    pkgs.curl
    # ...
  ];
}
```

See [GLIBC_REPLACEMENT.md](./GLIBC_REPLACEMENT.md) for technical details.

## Included Packages

### System Packages
- git, curl, wget
- file, jq, ripgrep
- htop, tmux
- neovim

### Development Tools
- nodejs (for claude-code, etc.)
- Python with packages
- Build essentials

### Shell Configuration
- zsh with oh-my-zsh
- fzf integration
- Syntax highlighting
- History search

## Troubleshooting

### Binary crashes with "Bad system call"

The binary is using standard glibc instead of Android-patched glibc. Ensure the package is wrapped with `patchPackageForAndroidGlibc`.

Check interpreter:
```bash
patchelf --print-interpreter /path/to/binary
# Should show: /nix/store/.../glibc-android-2.40-66/lib/ld-linux-aarch64.so.1
```

### Build failures

1. Ensure you have enough storage space (~5GB recommended)
2. Check network connectivity for binary cache
3. Try `nix-collect-garbage -d` to free space

### Home-manager errors

If home-manager fails to activate:
```bash
# Check home-manager status
home-manager generations

# Rebuild with verbose output
nix-on-droid switch --flake . --show-trace
```

## Differences from Desktop/Server

| Feature | Desktop/Server | Nix-on-Droid |
|---------|---------------|--------------|
| Init system | systemd | Android init |
| glibc | Standard | Android-patched |
| GUI | GNOME/Plasma | Terminal only |
| Root access | Full | Limited (proot) |

## Related Documentation

- [GLIBC_REPLACEMENT.md](./GLIBC_REPLACEMENT.md) - Android glibc technical details
- [../CLAUDE.md](../CLAUDE.md) - Repository overview and conventions
- [../README.md](../README.md) - Main project README
