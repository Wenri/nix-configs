# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a NixOS configuration repository based on the [nix-starter-config](https://github.com/Misterio77/nix-starter-config) template. It contains:
- **Single unified flake** at root managing 6 NixOS hosts
- **Unified infrastructure** in `common/` (overlays, modules, packages, home-manager)
- **Per-host configurations** in `hosts/` directory
- **All users are the same person: Bingchen Gong (username: wenri)**

## Repository Structure

### common/ - Unified Infrastructure (Exported)

Shared infrastructure providing identical userspace across all 6 hosts:

**Infrastructure** (all exported via flake outputs):
- `overlays/default.nix` - Package overlays:
  - `additions` - Custom packages from common/pkgs
  - `modifications` - Package modifications (e.g., fcitx5-rime-lua)
  - `unstable-packages` - Access to nixpkgs-unstable via `pkgs.unstable.*`
  - `master-packages` - Access to nixpkgs-master via `pkgs.master.*`
  - NUR (Nix User Repository) integration for community packages
  - nix-vscode-extensions for VS Code marketplace extensions
  - `modules/nixos/` - Exportable NixOS modules:
    - `common-base.nix` - Shared overlays + nix settings used everywhere
    - `server-base.nix` - Base server configuration with overlays
  - `users.nix` - Desktop user configuration
  - `locale.nix` - Locale and timezone settings
  - `secrets.nix` - Secrets management configuration
  - `tailscale.nix` - Tailscale VPN configuration
  - `disk-config.nix` - Disko disk partitioning
- `modules/home-manager/` - Empty, ready for exportable home-manager modules
- `pkgs/` - Custom package definitions (example-package)

**Core home-manager modules** (auto-imported via `common/home-manager/default.nix`):
- `core/default.nix` - Core profile combining CLI essentials + git/zsh/ssh/gh/program defaults
- `core/packages.nix` - Essential CLI tools (tmux, htop, nodejs, claude-code, cursor-cli, gemini-cli, iperf3, jq, file, parted)
- `core/programs.nix` - Base program enables (home-manager, tmux, vim)
- `core/git.nix` - Complete git configuration with user details, 1Password SSH signing
- `core/zsh.nix` - Complete zsh configuration (oh-my-zsh, completion, syntax highlighting, history)
- `core/ssh.nix` - SSH configuration with 1Password agent, GitHub port 443 workaround
- `core/gh.nix` - GitHub CLI configuration

**Optional home-manager modules** (imported explicitly when needed):
- `desktop/packages.nix` - GUI applications (Discord, Slack, Zoom, Chrome, etc.)
- `desktop/default.nix` - Desktop program bundle (Firefox, VS Code, Emacs, GNOME, Rime, optional WeChat)
- `desktop/emacs.nix`, `desktop/firefox`, `desktop/gnome`, `desktop/rime`, `desktop/vscode`, `desktop/wechat` - individual program modules
- `development/packages.nix` - Language/toolchain bundles (Agda, Elixir, Haskell, LaTeX, Python, Typst)
- `development/coq.nix` - Coq proof assistant with NUR packages (lngen, ott-sweirich)
- `development/pcloud.nix` - pCloud with patches
  - `rime/` - Rime input method
  - `vscode/` - VS Code settings and vscode-marketplace extensions
  - `emacs.nix` - Emacs configuration
  - `firefox/` - Firefox with NUR extensions (1Password, uBlock Origin, Translate)
  - `gnome.nix` - GNOME desktop customizations

**Result**: All 6 hosts share identical userspace and infrastructure.

### Root flake.nix - Single Unified Flake

The root `flake.nix` manages all 6 hosts with a single source of truth:

```nix
hosts = {
  wslnix       = { system = "x86_64-linux";   username = "wenri"; type = "wsl"; };
  nixos-gnome  = { system = "x86_64-linux";   username = "wenri"; type = "desktop"; };
  nixos-plasma6= { system = "x86_64-linux";   username = "wenri"; type = "desktop"; };
  irif         = { system = "x86_64-linux";   username = "wenri"; type = "desktop"; };
  matrix       = { system = "x86_64-linux";   username = "wenri"; type = "server"; };
  freenix      = { system = "aarch64-linux";  username = "wenri"; type = "server"; };
}
```

**Features:**
- Auto-generates all `nixosConfigurations` and `homeConfigurations`
- Type-based module loading (wsl, desktop, server)
- Exports overlays, modules, and packages from `common/`
- Integrated home-manager as NixOS module
- Single `nix flake update` updates all hosts

### hosts/ - Per-Host Configurations

Each host has its own directory with minimal configuration:

**wslnix/** (WSL)
- `configuration.nix` - WSL system config, imports from `common/modules/nixos/`
- `users.nix` - WSL-specific user configuration
- `home.nix` - Imports common home-manager modules only

**nixos-gnome/, nixos-plasma6/, irif/** (Desktops)
- `configuration.nix` - Desktop config, imports `common/modules/nixos/users.nix`, `locale.nix`, `secrets.nix`
- `hardware-configuration.nix` - Hardware-specific configuration
- `home.nix` - Imports `core.default` + `desktop.default` + `development`

**matrix/, freenix/** (Servers)
- `configuration.nix` - Server config, imports `common/modules/nixos/server-base.nix`, `users.nix`, `tailscale.nix`
- `facter.json` - nixos-facter hardware detection
- `synapse.nix` (matrix only) - Matrix Synapse server configuration
- `home.nix` - Imports common home-manager modules only

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

**IMPORTANT:** Always use the `--sudo` flag instead of running nixos-rebuild with `sudo`. Additionally, in zsh (the default shell), you **must quote** flake references containing `#` because zsh treats `#` as a special glob character.

```bash
# Apply system configuration for servers
nixos-rebuild switch --sudo --flake '.#matrix'
nixos-rebuild switch --sudo --flake '.#freenix'

# Apply for desktops
nixos-rebuild switch --sudo --flake '.#nixos-gnome'
nixos-rebuild switch --sudo --flake '.#nixos-plasma6'
nixos-rebuild switch --sudo --flake '.#irif'

# Apply for WSL
nixos-rebuild switch --sudo --flake '.#wslnix'

# Test without switching (dry run)
nixos-rebuild test --sudo --flake '.#hostname'

# Build without activating
nixos-rebuild build --sudo --flake '.#hostname'
```

**Why quote flake references in zsh?**

```bash
# ❌ WRONG in zsh - will fail with "no matches found"
nixos-rebuild switch --sudo --flake .#wslnix

# ✅ CORRECT in zsh - quote the flake reference
nixos-rebuild switch --sudo --flake '.#wslnix'

# ✅ Also works - double quotes
nixos-rebuild switch --sudo --flake ".#wslnix"
```

This issue only affects zsh. In bash, `#` starts a comment only at the beginning of a word, so `.#wslnix` works without quotes.

### Home Manager

**Home-manager is now integrated into NixOS configurations.**
A single `nixos-rebuild switch` command updates both system and user environment.

```bash
# Single command updates both NixOS and home-manager
nixos-rebuild switch --sudo --flake '.#matrix'
nixos-rebuild switch --sudo --flake '.#wslnix'

# Standalone home-manager still available for backward compatibility
home-manager switch --flake '.#wenri@matrix'
home-manager switch --flake '.#wenri@freenix'
home-manager switch --flake '.#wenri@wslnix'
home-manager switch --flake '.#wenri@nixos-gnome'
```

### Building Custom Packages
```bash
# Build custom package from common/pkgs/ (exported by the unified flake)
nix build '.#package-name'

# Enter development shell with package
nix shell '.#package-name'

# Example: building the example-package
nix build '.#example-package'
```

### Formatting
```bash
# Format all Nix files (uses alejandra)
nix fmt
```

## Key Architecture Details

### Modern Flake Architecture (2025)

The unified flake follows a modernized architecture:

**Single Source of Truth:**
- `hosts` attribute set in root `flake.nix` defines all 6 system configurations
- Auto-generates `nixosConfigurations` and `homeConfigurations` using `lib.mapAttrs`
- Eliminates redundant declarations and reduces code duplication

**Proper Package Structure:**
- Uses `mkPkgs` helper function for creating package sets
- Packages output uses `forAllSystems` for proper cross-platform support
- Formatter output configured for `nix fmt` using alejandra

**Home-Manager Integration:**
- Integrated as NixOS module (not standalone)
- Uses `home-manager.useGlobalPkgs` and `home-manager.useUserPackages`
- Single command updates both system and user environment
- Backward compatible standalone configurations still available

**Variable System:**
- Per-host username configuration in `hosts` attribute
- `hostname` and `username` passed through `specialArgs` to all modules
- Automatic derivation of paths (e.g., facter files from hostname)

### Host Type Features

**WSL (wslnix):**
- NixOS-WSL integration for Windows development
- Tailscale with userspace networking
- Dynamic username support

**Desktop (nixos-gnome, nixos-plasma6, irif):**
- GNOME and Plasma6 desktop environments
- ZFS support with LUKS encryption
- VMware guest tools integration
- Full GUI applications and development environments
- Input method: fcitx5 with Rime (using modified fcitx5-rime-lua from common overlays)

**Server (matrix, freenix):**
- Uses **nixos-facter** for hardware detection instead of traditional `hardware-configuration.nix`
- Employs **disko** for declarative disk partitioning
- Configured for remote deployment via **nixos-anywhere**
- Tailscale VPN with network optimization
- System features: Docker, fail2ban, openssh, Matrix Synapse (matrix only)
- Multi-architecture support: x86_64-linux and aarch64-linux
- Swap: Both file-based swap (2GB) and zram (30% of RAM with zstd compression)
- System tools: ethtool, usbutils (lsusb), curl, git, vim, wget, jq
- Passwordless sudo enabled for wheel group
- systemd-oomd enabled for OOM protection

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

**The unified flake exports from common:**
```nix
overlays = import ./common/overlays {inherit inputs;};
nixosModules = import ./common/modules/nixos;
homeModules = import ./common/modules/home-manager;
packages = forAllSystems (system: import ./common/pkgs {pkgs = mkPkgs system;});
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

#### Server host configurations (matrix, freenix)
- Disables global flake registry and channels (opinionated pure flake setup)
- Maps flake inputs to nix registry and NIX_PATH for compatibility
- Uses facter.reportPath from `facter.json` for hardware configuration
- Tailscale routing features enabled (can act as subnet router)
- Network optimization for Tailscale (rx-udp-gro-forwarding)

#### Desktop host configurations (nixos-gnome, nixos-plasma6, irif)
- Traditional `hardware-configuration.nix` for hardware detection
- ZFS with LUKS encryption support
- Desktop environment specific settings (GNOME, Plasma6)
- VMware guest tools integration

#### WSL host configuration (wslnix)
- NixOS-WSL specific integration
- Tailscale userspace networking mode
- Dynamic username support

#### Home-manager configurations
- nixpkgs config inherited from system (when using `useGlobalPkgs`)
- Home state version: 25.05
- User environment reloads systemd units on switch (`sd-switch`)
- Accepts `username` and `hostname` parameters from NixOS
- Core modules auto-imported from `common/home-manager/default.nix`
- Desktop-specific modules imported explicitly in desktop hosts

### Example: Modernized Flake Structure

**Adding a new host** is now as simple as adding one entry to the `hosts` attribute:

```nix
# In flake.nix
hosts = {
  freenix = { system = "aarch64-linux"; username = "wenri"; type = "server"; };
  matrix = { system = "x86_64-linux"; username = "wenri"; type = "server"; };
  newhost = { system = "x86_64-linux"; username = "wenri"; type = "server"; };  # ← Add this
};
```

This automatically generates:
- `nixosConfigurations.newhost`
- `homeConfigurations."wenri@newhost"`
- All necessary specialArgs and module imports
- Type-based module loading (wsl, desktop, or server)

**Helper functions** reduce boilerplate:
```nix
mkNixosSystem = { hostname, system, username, type }: ...
mkHomeConfiguration = { hostname, system, username }: ...
mkPkgs = system: import nixpkgs { inherit system; config.allowUnfree = true; };
```

**Benefits:**
- DRY principle: No duplicate hostname/system/username declarations
- Type safety: Impossible to mismatch system architectures or usernames
- Maintainability: Single source of truth for all 6 hosts
- Consistency: Same pattern across all host types (wsl, desktop, server)

## Git Workflow
Files must be tracked by git for Nix flakes to see them:
```bash
git add .  # Flakes only see tracked files
```
Files in `.gitignore` are invisible to Nix evaluations.

## Deployment with nixos-anywhere
For fresh installations of server hosts:
```bash
# With nixos-facter hardware detection
# Pattern: nixos-anywhere --flake '.#<hostname>' --generate-hardware-config nixos-facter ./hosts/<hostname>/facter.json <target>

# For matrix (x86_64-linux)
nixos-anywhere --flake '.#matrix' \
  --generate-hardware-config nixos-facter ./hosts/matrix/facter.json \
  root@target-host

# For freenix (aarch64-linux)
nixos-anywhere --flake '.#freenix' \
  --generate-hardware-config nixos-facter ./hosts/freenix/facter.json \
  root@target-host
```

## Important Notes
- **Single unified flake**: All 6 hosts managed by root `flake.nix`
- **Unified infrastructure**: All hosts share infrastructure from `common/` (overlays, modules, packages)
- **Unified userspace**: All users are the same person: Bingchen Gong (username: wenri)
- **All home-manager configuration identical**: Same packages, programs, and dotfiles across all environments
- System state version: 25.05
- Home state version: 25.05
- Custom packages accessible via `nix build '.#package-name'`
- Firefox extensions from NUR (1Password, uBlock Origin, Translate Web Pages)
- VS Code extensions from nix-vscode-extensions marketplace overlay
- Coq packages from NUR (lngen, ott-sweirich)
- Formatter set to `alejandra` - use `nix fmt` to format all Nix files
