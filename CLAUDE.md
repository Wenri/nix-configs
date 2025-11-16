# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS configuration repository based on the [nix-starter-config](https://github.com/Misterio77/nix-starter-config) template. It contains:
- **Template flakes** (`minimal/` and `standard/`) - starter configurations for new users
- **Live configuration** (`anywhere/`) - the active NixOS and home-manager setup for user wenri

## Repository Structure

### common/ - Unified Configuration Modules
**All users (wenri, nixos, xsnow) are the same person: Bingchen Gong**

Shared infrastructure and home-manager modules providing identical userspace across all environments:

**Infrastructure** (shared by anywhere/, minimal/, standard/):
- `overlays/default.nix` - Package overlays:
  - `additions` - Custom packages from common/pkgs
  - `modifications` - Package modifications (e.g., fcitx5-rime-lua)
  - `unstable-packages` - Access to nixpkgs-unstable
  - `master-packages` - Access to nixpkgs-master
  - NUR (Nix User Repository) integration for community packages
  - nix-vscode-extensions for VS Code marketplace extensions
- `modules/` - Custom NixOS and home-manager modules shared across all configurations
- `pkgs/` - Custom package definitions (example-package)

**Core home-manager modules** (auto-imported via `common/home-manager/default.nix`):
- `base-packages.nix` - Essential CLI tools (tmux, htop, nodejs, claude-code, cursor-cli, gemini-cli, iperf3, jq, file, parted)
- `git.nix` - Complete git configuration with user details, 1Password SSH signing
- `zsh.nix` - Complete zsh configuration (oh-my-zsh, completion, syntax highlighting, history)
- `ssh.nix` - SSH configuration with 1Password agent, GitHub port 443 workaround
- `gh.nix` - GitHub CLI configuration
- `programs.nix` - Base program enables (home-manager, tmux, vim)

**Optional home-manager modules** (imported explicitly when needed):
- `desktop-packages.nix` - GUI applications (Discord, Slack, Zoom, Chrome, etc.)
- `development/` - Development environments:
  - `coq.nix` - Coq proof assistant with NUR packages (lngen, ott-sweirich)
  - `haskell.nix` - GHC, Stack, Cabal, HLS
  - `latex.nix` - TeXLive full scheme
  - `python.nix` - Python with requests
  - `typst.nix` - Typst and Tinymist
  - `pcloud.nix` - pCloud with patches
- `programs/` - Desktop-specific program configurations:
  - `rime/` - Rime input method
  - `vscode/` - VS Code settings and vscode-marketplace extensions
  - `emacs.nix` - Emacs configuration
  - `firefox/` - Firefox with NUR extensions (1Password, uBlock Origin, Translate)
  - `gnome.nix` - GNOME desktop customizations

**Result**: All three configs have identical userspace and share the same infrastructure (overlays, modules, pkgs).

### anywhere/ - Active Configuration
The primary configuration in active use:
- `flake.nix` - Defines system configurations and home-manager setups
  - NixOS configs: `freenix` (aarch64-linux), `matrix` (x86_64-linux)
  - Home configs: `wenri@matrix`, `wenri@freenix`
  - Exports overlays, modules, and packages from `../common/`
  - Includes NUR and nix-vscode-extensions inputs
- `nixos/` - System-level NixOS configurations
  - `common.nix` - Shared base configuration for all systems with common overlays
  - `host-matrix.nix` - Matrix server config (imports common.nix + synapse.nix)
  - `host-freenix.nix` - Freenix-specific config (imports common.nix)
  - `disk-config.nix` - Disko declarative disk partitioning (LVM on GPT)
  - `users.nix` - User accounts, permissions, and user-specific programs
  - `synapse.nix` - Matrix Synapse server configuration module
  - `tailscale.nix` - Tailscale VPN configuration module with network optimization
  - `facter-freenix.json` / `facter-matrix.json` - Hardware detection from nixos-facter (follows pattern: `facter-${hostname}.json`)
- `home-manager/` - User environment configurations
  - `home.nix` - Main home-manager entrypoint (imports unified common modules only)

### standard/ - Standard Template
Extended template with desktop environments:
- `flake.nix` - Desktop-focused configuration
  - Multiple NixOS configurations: `nixos-gnome`, `nixos-plasma6`, `irif`
  - Home configs for user `xsnow`
  - Exports overlays, modules, and packages from `../common/`
  - Includes NUR and nix-vscode-extensions inputs
- `nixos/` - System-level NixOS configurations with common overlays
  - Desktop environment configurations (GNOME, Plasma6)
  - ZFS support with LUKS encryption
  - VMware guest tools integration
- `home-manager/` - User environment configurations
  - `home.nix` - Imports unified common + desktop-packages + development + programs from common/

### minimal/ - NixOS-WSL Configuration
NixOS-WSL configuration with modern architecture:
- `flake.nix` - Modern flake architecture with NixOS-WSL integration
  - NixOS config: `wslnix` (x86_64-linux)
  - Home config: `nixos@wslnix`
  - Uses `mkNixosSystem` and `mkHomeConfiguration` helper functions
  - Single source of truth `hosts` attribute set
  - Integrated home-manager as NixOS module
  - Exports overlays, modules, and packages from `../common/`
  - Includes NUR and nix-vscode-extensions inputs
- `nixos/` - System-level configurations
  - `common.nix` - Main system configuration with WSL support, Tailscale userspace networking, common overlays
  - `users.nix` - User accounts with dynamic username support
- `home-manager/` - User environment configurations
  - `home.nix` - Main home-manager entrypoint (imports unified common modules only)

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
sudo nixos-rebuild switch --flake /home/wenri/nix-configs/anywhere#matrix
sudo nixos-rebuild switch --flake /home/wenri/nix-configs/anywhere#freenix

# Apply from standard/ (replace hostname with actual)
sudo nixos-rebuild switch --flake /home/wenri/nix-configs/standard#nixos-gnome
sudo nixos-rebuild switch --flake /home/wenri/nix-configs/standard#nixos-plasma6

# Apply from minimal/ (NixOS-WSL)
sudo nixos-rebuild switch --flake /home/nixos/nix-configs/minimal#wslnix

# Test without switching (dry run)
sudo nixos-rebuild test --flake .#hostname

# Build without activating
sudo nixos-rebuild build --flake .#hostname
```

### Home Manager

**Home-manager is now integrated into NixOS configurations.**
A single `nixos-rebuild switch` command updates both system and user environment.

```bash
# Single command updates both NixOS and home-manager
sudo nixos-rebuild switch --flake /home/wenri/nix-configs/anywhere#matrix

# Standalone home-manager still available for backward compatibility
home-manager switch --flake /home/wenri/nix-configs/anywhere#wenri@matrix
home-manager switch --flake /home/wenri/nix-configs/anywhere#wenri@freenix
home-manager switch --flake /home/nixos/nix-configs/minimal#nixos@wslnix
```

### Building Custom Packages
```bash
# Build custom package from common/pkgs/ (exported by all flakes)
nix build /home/wenri/nix-configs/standard#package-name
nix build /home/wenri/nix-configs/anywhere#package-name
nix build /home/nixos/nix-configs/minimal#package-name

# Enter development shell with package
nix shell /home/wenri/nix-configs/standard#package-name
```

### Formatting
```bash
# Format all Nix files (uses alejandra)
nix fmt
```

## Key Architecture Details

### Modern Flake Architecture (2025)

Both `anywhere/` and `standard/` now follow a modernized architecture:

**Single Source of Truth:**
- `hosts` attribute set defines all system configurations
- Auto-generates `nixosConfigurations` and `homeConfigurations` using `lib.mapAttrs`
- Eliminates redundant declarations and reduces code duplication

**Proper Package Structure:**
- Replaced `legacyPackages` with `mkPkgs` helper function
- Packages output uses `forAllSystems` for proper cross-platform support
- Formatter output configured for `nix fmt` using alejandra

**Home-Manager Integration:**
- Integrated as NixOS module (not standalone)
- Uses `home-manager.useGlobalPkgs` and `home-manager.useUserPackages`
- Single command updates both system and user environment
- Backward compatible standalone configurations still available

**Variable System:**
- `defaultUsername` variable for consistent user configuration
- `hostname` and `username` passed through `specialArgs` to all modules
- Automatic derivation of paths (e.g., facter files from hostname)

### anywhere/ Configuration
- Uses **nixos-facter** for hardware detection instead of traditional `hardware-configuration.nix`
- Employs **disko** for declarative disk partitioning (see `disk-config.nix`)
- Configured for remote deployment via **nixos-anywhere**
- **Refactored architecture**: Common configuration in `common.nix` reduces duplication
- **Unified overlays** from `common/` providing NUR, vscode-extensions, unstable packages
- System features: Tailscale VPN, Docker, fail2ban, openssh, Matrix Synapse
- Multi-architecture support: x86_64-linux and aarch64-linux
- Swap: Both file-based swap (2GB) and zram (30% of RAM with zstd compression)
- System tools: ethtool, usbutils (lsusb), curl, git, vim, wget, jq
- Passwordless sudo enabled for wheel group
- systemd-oomd enabled for OOM protection

### standard/ Configuration
- Extended template with desktop environments: GNOME, Plasma6
- **Unified infrastructure** from `common/` (modules, overlays, packages)
- Desktop features: ZFS with LUKS encryption, VMware guest tools
- Input method: fcitx5 with Rime (using modified fcitx5-rime-lua from common overlays)
- All overlays, modules, and packages exported from `common/`

### Flake Input Pattern
All configurations follow the pattern:
```nix
inputs = {
  nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  nixpkgs-master.url = "github:nixos/nixpkgs/master";
  home-manager.url = "github:nix-community/home-manager";
  home-manager.inputs.nixpkgs.follows = "nixpkgs";
  nur.url = "github:nix-community/NUR";
  nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";
}
```
The `follows` ensures home-manager uses the same nixpkgs revision as the system, avoiding version conflicts. NUR provides Firefox extensions and Coq packages, while nix-vscode-extensions provides VS Code marketplace extensions.

### Special Args Pattern
Configurations pass `inputs` and `outputs` to modules via `specialArgs`:
```nix
specialArgs = {inherit inputs outputs;};
```
This makes flake inputs and outputs accessible in all imported modules.

### Module System and Overlays
**Unified Infrastructure in `common/`:**
- Custom modules go in `common/modules/nixos/` (system) or `common/modules/home-manager/` (user)
- Modules must be registered in respective `default.nix` files
- Overlays in `common/overlays/default.nix` provide:
  - `additions` - Custom packages from `common/pkgs/`
  - `modifications` - Package modifications (e.g., fcitx5-rime-lua with Lua support)
  - `unstable-packages` - Access to nixpkgs-unstable via `pkgs.unstable.*`
  - `master-packages` - Access to nixpkgs-master via `pkgs.master.*`
  - NUR overlay for Firefox extensions and community packages
  - nix-vscode-extensions overlay for VS Code marketplace extensions

**All flakes export from common:**
```nix
overlays = import ../common/overlays {inherit inputs;};
nixosModules = import ../common/modules/nixos;
homeManagerModules = import ../common/modules/home-manager;
packages = forAllSystems (system: import ../common/pkgs {pkgs = mkPkgs system;});
```

### Home Manager Integration
**Fully integrated into NixOS as a module:**
- Added `inputs.home-manager.nixosModules.home-manager` in `mkNixosSystem`
- Configured `home-manager.users.${username} = import ./home-manager/home.nix;`
- Enabled `home-manager.useGlobalPkgs = true` for shared package set
- Enabled `home-manager.useUserPackages = true` for per-user packages
- Single `nixos-rebuild switch` updates both system and user environment
- Standalone `homeConfigurations` still available for backward compatibility

### Important Configuration Details

#### anywhere/nixos/configuration.nix
- Disables global flake registry and channels (opinionated pure flake setup)
- Maps flake inputs to nix registry and NIX_PATH for compatibility
- Uses facter.reportPath for hardware configuration
- Tailscale routing features enabled (can act as subnet router)
- Network optimization for Tailscale (rx-udp-gro-forwarding)

#### anywhere/home-manager/home.nix
- nixpkgs config inherited from system (when using `useGlobalPkgs`)
- Home state version: 25.05
- User environment reloads systemd units on switch (`sd-switch`)
- Accepts `username` and `hostname` parameters from NixOS

### Example: Modernized Flake Structure

**Adding a new host** is now as simple as adding one entry to the `hosts` attribute:

```nix
# In flake.nix
hosts = {
  freenix = { system = "aarch64-linux"; };
  matrix = { system = "x86_64-linux"; };
  newhost = { system = "x86_64-linux"; };  # ← Add this
};
```

This automatically generates:
- `nixosConfigurations.newhost`
- `homeConfigurations."wenri@newhost"` (or `"xsnow@newhost"` in standard/)
- All necessary specialArgs and module imports

**Helper functions** reduce boilerplate:
```nix
mkNixosSystem = { hostname, system, username ? defaultUsername }: ...
mkHomeConfiguration = { hostname, system, username ? defaultUsername }: ...
mkPkgs = system: import nixpkgs { inherit system; config.allowUnfree = true; };
```

**Benefits:**
- DRY principle: No duplicate hostname/system declarations
- Type safety: Impossible to mismatch system architectures
- Maintainability: Single source of truth for all hosts
- Consistency: Same pattern across anywhere/ and standard/

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
# Pattern: nixos-anywhere --flake .#<hostname> --generate-hardware-config nixos-facter ./nixos/facter-<hostname>.json <target>

# For matrix (x86_64-linux)
nixos-anywhere --flake .#matrix \
  --generate-hardware-config nixos-facter ./nixos/facter-matrix.json \
  root@target-host

# For freenix (aarch64-linux)
nixos-anywhere --flake .#freenix \
  --generate-hardware-config nixos-facter ./nixos/facter-freenix.json \
  root@target-host
```

## Important Notes
- The repository README mentions it's "a little out of date" and pending refactor
- All three configurations (`anywhere/`, `minimal/`, `standard/`) are actively maintained
- **Unified infrastructure**: All configurations share infrastructure from `common/` (overlays, modules, packages)
- **Unified userspace**: All users (wenri, nixos, xsnow) are the same person with identical home-manager configuration
- System state version: 25.05
- Custom packages are accessible via `nix build .#package-name` from any of the three flakes
- Firefox extensions from NUR (1Password, uBlock Origin, Translate Web Pages)
- VS Code extensions from nix-vscode-extensions marketplace overlay
- Coq packages from NUR (lngen, ott-sweirich)
- The formatter is set to `alejandra` across all configurations
