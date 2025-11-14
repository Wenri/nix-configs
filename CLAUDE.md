# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS configuration repository based on the [nix-starter-config](https://github.com/Misterio77/nix-starter-config) template. It contains:
- **Template flakes** (`minimal/` and `standard/`) - starter configurations for new users
- **Live configuration** (`anywhere/`) - the active NixOS and home-manager setup for user wenri

## Repository Structure

### anywhere/ - Active Configuration
The primary configuration in active use:
- `flake.nix` - Defines system configurations and home-manager setups
  - NixOS configs: `freevm-nixos-facter` (aarch64-linux), `generic-nixos-facter` (x86_64-linux)
  - Home configs: `wenri@nixos`, `wenri@freenix`
- `nixos/` - System-level NixOS configurations
  - `common.nix` - Shared base configuration for all systems
  - `host-generic.nix` - Generic system config (imports common.nix + synapse.nix)
  - `host-freenix.nix` - Freenix-specific config (imports common.nix)
  - `disk-config.nix` - Disko declarative disk partitioning (LVM on GPT)
  - `users.nix` - User account definitions
  - `synapse.nix` - Matrix Synapse server configuration
  - `facter.json` / `facter-free.json` - Hardware detection from nixos-facter
- `home-manager/` - User environment configurations
  - `home.nix` - Main home-manager entrypoint
  - `packages.nix` - User package declarations
  - `programs/` - Program-specific configurations (git, ssh, zsh)

### standard/ - Standard Template
Extended template with additional structure:
- `modules/` - Custom NixOS and home-manager modules
- `overlays/` - Package modifications and custom package integration
- `pkgs/` - Custom package definitions
- Multiple NixOS configurations: `nixos-gnome`, `nixos-plasma6`, `irif`
- Home configs for user `xsnow`

### minimal/ - Minimal Template
Basic flake structure with just NixOS and home-manager configurations.

## Common Development Commands

### Flake Management
```bash
# Update all flake inputs to latest versions
nix flake update

# Update specific input
nix flake lock --update-input nixpkgs

# Show flake metadata
nix flake show

# Check flake for errors
nix flake check
```

### NixOS System Configuration
```bash
# Apply system configuration (from anywhere/)
sudo nixos-rebuild switch --flake /home/wenri/nix-configs/anywhere#generic-nixos-facter
sudo nixos-rebuild switch --flake /home/wenri/nix-configs/anywhere#freevm-nixos-facter

# Apply from standard/ (replace hostname with actual)
sudo nixos-rebuild switch --flake /home/wenri/nix-configs/standard#nixos-gnome
sudo nixos-rebuild switch --flake /home/wenri/nix-configs/standard#nixos-plasma6

# Test without switching (dry run)
sudo nixos-rebuild test --flake .#hostname

# Build without activating
sudo nixos-rebuild build --flake .#hostname
```

### Home Manager
```bash
# Apply home-manager configuration
home-manager switch --flake /home/wenri/nix-configs/anywhere#wenri@nixos
home-manager switch --flake /home/wenri/nix-configs/anywhere#wenri@freenix

# Build without switching
home-manager build --flake .#username@hostname
```

### Building Custom Packages (standard/)
```bash
# Build custom package from pkgs/
nix build /home/wenri/nix-configs/standard#package-name

# Enter development shell with package
nix shell /home/wenri/nix-configs/standard#package-name
```

### Formatting
```bash
# Format all Nix files (uses alejandra)
nix fmt
```

## Key Architecture Details

### anywhere/ Configuration
- Uses **nixos-facter** for hardware detection instead of traditional `hardware-configuration.nix`
- Employs **disko** for declarative disk partitioning (see `disk-config.nix`)
- Configured for remote deployment via **nixos-anywhere**
- **Refactored architecture**: Common configuration in `common.nix` reduces duplication
- System features: Tailscale VPN, Docker, fail2ban, openssh, Matrix Synapse
- Multi-architecture support: x86_64-linux and aarch64-linux
- Swap: Both file-based swap (2GB) and zram (30% of RAM with zstd compression)
- System tools: ethtool, usbutils (lsusb), curl, git, vim, wget
- Passwordless sudo enabled for wheel group
- systemd-oomd enabled for OOM protection

### Flake Input Pattern
All configurations follow the pattern:
```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  home-manager.url = "github:nix-community/home-manager";
  home-manager.inputs.nixpkgs.follows = "nixpkgs";
}
```
The `follows` ensures home-manager uses the same nixpkgs revision as the system, avoiding version conflicts.

### Special Args Pattern
Configurations pass `inputs` and `outputs` to modules via `specialArgs`:
```nix
specialArgs = {inherit inputs outputs;};
```
This makes flake inputs and outputs accessible in all imported modules.

### Module System
In `standard/`:
- Custom modules go in `modules/nixos/` (system) or `modules/home-manager/` (user)
- Modules must be registered in respective `default.nix` files
- Overlays in `overlays/default.nix` provide package modifications and access to unstable packages

### Home Manager Integration
Currently used as standalone (separate from NixOS rebuild). To integrate into NixOS:
1. Import `inputs.home-manager.nixosModules.home-manager` in NixOS config
2. Configure via `home-manager.users.username = import ./path/to/home.nix;`
3. Use `nixos-rebuild` instead of `home-manager` command

### Important Configuration Details

#### anywhere/nixos/configuration.nix
- Disables global flake registry and channels (opinionated pure flake setup)
- Maps flake inputs to nix registry and NIX_PATH for compatibility
- Uses facter.reportPath for hardware configuration
- Tailscale routing features enabled (can act as subnet router)
- Network optimization for Tailscale (rx-udp-gro-forwarding)

#### anywhere/home-manager/home.nix
- Allows unfree packages
- Home state version: 24.11
- User environment reloads systemd units on switch (`sd-switch`)

## Git Workflow
Files must be tracked by git for Nix flakes to see them:
```bash
git add .  # Flakes only see tracked files
```
Files in `.gitignore` are invisible to Nix evaluations.

## Deployment with nixos-anywhere
For fresh installations using the anywhere/ configuration:
```bash
# With nixos-facter hardware detection
nixos-anywhere --flake .#generic-nixos-facter \
  --generate-hardware-config nixos-facter ./nixos/facter.json \
  <hostname>
```

## Important Notes
- The repository README mentions it's "a little out of date" and pending refactor
- `anywhere/` appears to be the actively maintained configuration
- System state version for `anywhere/`: 24.11
- Custom packages in `standard/` are accessible via `nix build .#package-name`
- The formatter is set to `alejandra` across all configurations
