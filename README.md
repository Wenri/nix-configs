# NixOS Configurations (2025 Edition)

**Personal NixOS configurations** featuring unified infrastructure and modern best practices.

> **Note:** This is a personal configuration repository based on [nix-starter-config](https://github.com/Misterio77/nix-starter-config). All configurations share unified infrastructure from `common/` - the same overlays, modules, packages, and userspace are used across WSL, desktop, and server deployments.

This repository contains **6 NixOS hosts + 1 nix-on-droid** managed by a single unified flake:
- **wslnix** - NixOS-WSL for Windows development
- **nixos-gnome, nixos-plasma6, irif** - Desktop environments (GNOME, Plasma6)
- **matrix, freenix** - Production servers (Matrix Synapse, ARM server)
- **nix-on-droid** - Android/Termux development environment

Features modern architecture with integrated home-manager, auto-generated configurations, and nixos-anywhere deployment.

## Unified Architecture

**All configurations share infrastructure from `common/`:**
- **Overlays** - NUR (Firefox extensions, Coq packages), vscode-marketplace, unstable/master packages
- **Modules** - Exportable NixOS modules (common-base, server-base, users, locale, tailscale, etc.)
- **Packages** - Custom package definitions
- **Home-Manager** - Identical userspace across all environments (all users are the same person)

## What This Provides

### Single Unified Flake

All 6 hosts are defined in a single `flake.nix` with the `hosts` attribute:

```nix
hosts = {
  wslnix       = { system = "x86_64-linux";   username = "nixos"; type = "wsl"; };
  nixos-gnome  = { system = "x86_64-linux";   username = "xsnow"; type = "desktop"; };
  nixos-plasma6= { system = "x86_64-linux";   username = "xsnow"; type = "desktop"; };
  irif         = { system = "x86_64-linux";   username = "xsnow"; type = "desktop"; };
  matrix       = { system = "x86_64-linux";   username = "wenri"; type = "server"; };
  freenix      = { system = "aarch64-linux";  username = "wenri"; type = "server"; };
}
```

### Host Types

**WSL (wslnix)**
- NixOS-WSL integration for Windows development
- Tailscale with userspace networking
- Dynamic username support

**Desktop (nixos-gnome, nixos-plasma6, irif)**
- GNOME and Plasma6 desktop environments
- ZFS support with LUKS encryption
- VMware guest tools integration
- Full GUI applications and development environments
- Input method: fcitx5 with Rime

**Server (matrix, freenix)**
- nixos-anywhere for remote deployment
- nixos-facter for modern hardware detection
- Disko for declarative disk partitioning
- Matrix Synapse server (matrix)
- Multi-architecture support (x86_64 and aarch64)
- Tailscale VPN with network optimization

**Nix-on-Droid (Android)**
- nix-community/nix-on-droid for Android/Termux
- Custom Android-patched glibc 2.40 with Termux patches
- Fakechroot login system (modified for proper login shell support)
- Master home-manager with advanced template pattern
- Full development environment (zsh, git, neovim, claude-code)
- `self.submodules = true` for git submodule support
- See `docs/NIX-ON-DROID.md` for detailed configuration guide

### Shared Features

- ✅ **Integrated home-manager** - Single `nixos-rebuild switch` updates both system and user
- ✅ **Unified userspace** - All users (wenri, nixos, xsnow) are the same person with identical config
- ✅ **Exportable modules** - Server and desktop modules available as `nixosModules.*`
- ✅ **Development environments** - Coq, Haskell, LaTeX, Python, Typst
- ✅ **Modern 2025 architecture** - Single source of truth, auto-generated configurations

## Modern Architecture (2025)

All 6 hosts are managed by a single unified flake with shared infrastructure:

### Unified Infrastructure (`common/`)

**All configurations share the same infrastructure:**

```
common/
├── overlays/           # Package overlays (exported)
│   └── default.nix    # NUR, vscode-marketplace, unstable, master packages
├── modules/           # Exportable modules
│   ├── nixos/        # NixOS modules (common-base, server-base, users, locale, tailscale, etc.)
│   └── home-manager/ # Home-manager modules (empty, ready for future use)
├── pkgs/             # Custom packages (exported)
│   └── default.nix   # Package definitions
└── home-manager/     # Unified userspace configuration
    ├── default.nix           # Exports (core, desktop, dev, etc.)
    ├── core/                 # Core profile used by every host
    │   ├── default.nix       # Imports CLI packages + git/zsh/ssh/gh/program defaults
    │   ├── packages.nix      # Essential CLI tools
    │   ├── programs.nix      # Base program enables (home-manager, tmux, vim, ...)
    │   ├── git.nix           # Git config with 1Password signing
    │   ├── zsh.nix           # Zsh with oh-my-zsh
    │   ├── ssh.nix           # SSH with 1Password agent
    │   └── gh.nix            # GitHub CLI
    ├── desktop/              # Desktop-specific modules
    │   ├── packages.nix      # GUI applications (optional)
    │   ├── default.nix       # Desktop program bundle (Firefox, VS Code, etc.)
    │   ├── emacs.nix         # Emacs configuration
    │   ├── firefox/
    │   ├── gnome/
    │   ├── rime/
    │   ├── vscode/
    │   └── wechat/
    └── development/          # Dev environments (optional)
        └── packages.nix      # Language/toolchain bundles
```

**Benefits:**
- **Zero duplication** - Infrastructure defined once, used everywhere
- **Identical userspace** - Same packages, config, extensions across all environments
- **Shared overlays** - NUR Firefox extensions, VS Code marketplace, unstable packages
- **Single source of truth** - All users (wenri, nixos, xsnow) are the same person

### Single Source of Truth (Per-Config)
```nix
# Define all hosts in one place
hosts = {
  freenix = { system = "aarch64-linux"; };
  matrix = { system = "x86_64-linux"; };
  newhost = { system = "x86_64-linux"; };  # ← Add new host here
};

# Configurations auto-generated using lib.mapAttrs
nixosConfigurations = lib.mapAttrs (hostname: cfg: mkNixosSystem { ... }) hosts;
homeConfigurations = lib.mapAttrs' (hostname: cfg: ...) hosts;
```

**Benefits:**
- No duplicate declarations
- Type-safe (impossible to mismatch system architectures)
- Add new host with just one line
- Consistent across all configurations

### Integrated Home-Manager
```bash
# Before: Two separate commands
sudo nixos-rebuild switch --flake .#matrix
home-manager switch --flake .#wenri@matrix

# After: Single command updates both
sudo nixos-rebuild switch --flake .#matrix
```

Home-manager is now a NixOS module with:
- `home-manager.useGlobalPkgs = true` - Shared package set
- `home-manager.useUserPackages = true` - Per-user packages
- Automatic inheritance of nixpkgs config and overlays
- Backward-compatible standalone configs still available

### Variable System
```nix
# In flake.nix
defaultUsername = "wenri";  # or "xsnow" in standard/

# Passed to all modules via specialArgs
specialArgs = { inherit inputs outputs hostname username; };

# Used in modules
users.users.${username} = { ... };  # Auto-uses correct username
networking.hostName = hostname;      # Auto-set from hosts
```

### Proper Package Structure
```nix
# No more legacyPackages
mkPkgs = system: import nixpkgs {
  inherit system;
  config.allowUnfree = true;
};

# Proper packages output
packages = forAllSystems (system: import ./pkgs (mkPkgs system));

# Formatter for 'nix fmt'
formatter = forAllSystems (system: (mkPkgs system).alejandra);
```

## Getting Started

### Prerequisites

- NixOS installation (live or installed) - [Download NixOS](https://nixos.org/download#download-nixos)
- Or use `nix` and `home-manager` on any Linux/macOS - [Install Nix](https://nixos.org/download.html#nix)
- Git installed
- Nix 2.4+ with flakes enabled

### Using This Repository

This is a personal configuration repository with unified infrastructure. All 6 hosts share:
- **Same userspace** - Identical packages, programs, and dotfiles
- **Same overlays** - NUR extensions, vscode-marketplace, unstable packages
- **Same modules** - Exportable NixOS and home-manager modules

**To use a configuration:**
```bash
# For WSL
sudo nixos-rebuild switch --flake .#wslnix

# For desktop
sudo nixos-rebuild switch --flake .#nixos-gnome
sudo nixos-rebuild switch --flake .#nixos-plasma6
sudo nixos-rebuild switch --flake .#irif

# For servers
sudo nixos-rebuild switch --flake .#matrix
sudo nixos-rebuild switch --flake .#freenix

# For Android (nix-on-droid)
nix-on-droid switch --flake ~/.config/nix-on-droid
```

### Customization

Since all configurations share `common/`, you can customize once and benefit everywhere:

1. **Update user details** in `common/home-manager/git.nix`:
   - User name and email
   - SSH signing key

2. **Add packages** in `common/home-manager/`:
   - `core/packages.nix` - CLI tools (applies to all hosts)
   - `desktop/packages.nix` - GUI apps (applies to desktop profiles)
   - `development/packages.nix` - Language/toolchain bundles for dev hosts

3. **Configure desktop programs** directly in `common/home-manager/desktop/` (Firefox, VS Code, Emacs, Rime, etc.)

4. **Add new hosts:**
   - Update the `hosts` attribute in `flake.nix`
   - Create a directory in `hosts/yourhostname/`
   - Add `configuration.nix` and `home.nix`

5. **Update flake inputs:**
```bash
nix flake update
```

6. **Git commit your changes:**
```bash
git add .
git commit -m "Personal customizations"
```

## Usage

### NixOS System Configuration
```bash
# Apply configuration (updates both NixOS and home-manager)
sudo nixos-rebuild switch --flake .#wslnix        # For WSL
sudo nixos-rebuild switch --flake .#nixos-gnome   # For GNOME desktop
sudo nixos-rebuild switch --flake .#matrix        # For Matrix server

# Test without switching (dry run)
sudo nixos-rebuild test --flake .#hostname

# Build without activating
sudo nixos-rebuild build --flake .#hostname

# Install on a new system (from live medium)
nixos-install --flake .#hostname
```

### Home-Manager (Standalone)
```bash
# Standalone home-manager (backward compatibility)
home-manager switch --flake .#nixos@wslnix
home-manager switch --flake .#xsnow@nixos-gnome
home-manager switch --flake .#wenri@matrix

# If home-manager not installed
nix shell nixpkgs#home-manager
```

### Formatting
```bash
# Format all Nix files (uses alejandra)
nix fmt
```

### Remote Deployment with nixos-anywhere
```bash
# Pattern: nixos-anywhere --flake .#<hostname> --generate-hardware-config nixos-facter ./nixos/facter-<hostname>.json <target>

# Deploy to remote host
nixos-anywhere --flake .#matrix \
  --generate-hardware-config nixos-facter ./nixos/facter-matrix.json \
  root@target-host
```

## Configuration Details

### Repository Structure
```
nix-configs/
├── flake.nix          # Single unified flake for all 6 hosts
├── flake.lock         # Single lock file
├── common/            # Unified infrastructure (exported)
│   ├── overlays/     # Package overlays
│   ├── modules/
│   │   ├── nixos/   # Exportable NixOS modules
│   │   └── home-manager/ # Exportable home-manager modules
│   ├── pkgs/        # Custom packages
│   └── home-manager/ # Unified userspace configuration
├── hosts/            # Per-host configurations
│   ├── wslnix/
│   │   ├── configuration.nix # WSL system config
│   │   ├── users.nix         # WSL-specific users
│   │   └── home.nix          # Imports common modules
│   ├── nixos-gnome/
│   │   ├── configuration.nix
│   │   ├── hardware-configuration.nix
│   │   └── home.nix
│   ├── nixos-plasma6/
│   │   ├── configuration.nix
│   │   ├── hardware-configuration.nix
│   │   └── home.nix
│   ├── irif/
│   │   ├── configuration.nix
│   │   ├── hardware-configuration.nix
│   │   └── home.nix
│   ├── matrix/
│   │   ├── configuration.nix
│   │   ├── facter.json      # nixos-facter hardware detection
│   │   ├── synapse.nix      # Matrix Synapse config
│   │   └── home.nix
│   ├── freenix/
│   │   ├── configuration.nix
│   │   ├── facter.json
│   │   └── home.nix
│   └── nix-on-droid/
│       ├── configuration.nix  # nix-on-droid system + home-manager integration
│       └── home.nix           # zsh, git, fzf, claude-code, dev tools
└── secrets/           # Secrets (not in git)
    └── tailscale-auth.key
```

### Features
- **Modular Design**: Each service in its own module (tailscale, synapse, users)
- **Host-Specific Configs**: Minimal host files, only what's unique
- **Passwordless Sudo**: Configured for wheel group
- **System Tools**: ethtool, usbutils, curl, git, vim, wget, jq, ndisc6, iputils
- **Memory Management**: 2GB swap + zram (30% RAM, zstd) + systemd-oomd
- **Modern Architecture**: Single source of truth, auto-generation, variable system

### Adding a New Host

**Modern approach** - Just update `flake.nix`:

```nix
# In flake.nix
hosts = {
  freenix = { system = "aarch64-linux"; };
  matrix = { system = "x86_64-linux"; };
  newhost = { system = "x86_64-linux"; };  # ← Add this line
};
```

Then create `nixos/host-newhost.nix`:
```nix
{ lib, hostname, ... }: {
  imports = [ ./common.nix ];

  networking.hostName = hostname;  # Auto-set from hosts
  # Add host-specific configuration here
}
```

**That's it!** This automatically creates:
- `nixosConfigurations.newhost`
- `homeConfigurations."wenri@newhost"`
- Facter file path: `./nixos/facter-newhost.json`

No manual flake.nix configuration needed!

## Advanced Topics

### Dotfile Management
Besides packages, home-manager can manage your dotfiles. Use `home-configuration.nix` options for full Nix syntax configuration, or `xdg.configFile` to include existing dotfiles.

### User Passwords and Secrets
- Default: Prompted for root password during `nixos-install`
- Or use `initialPassword` for your user (change after first boot)
- Or use `passwordFile` for declarative password from file
- Advanced: [Secret management schemes](https://nixos.wiki/wiki/Comparison_of_secret_managing_schemes)

### Custom Packages
All custom packages are defined in `common/pkgs/` and exported by the flake:
```bash
# Build your package
nix build .#package-name

# Use in shell
nix shell .#package-name
```

Create a folder under `common/pkgs/` with a `default.nix` - it's automatically available in all configurations.

### Overlays
All overlays are defined in `common/overlays/default.nix` and exported:
- **additions** - Custom packages from `common/pkgs/`
- **modifications** - Package patches (e.g., fcitx5-rime-lua with Lua support)
- **unstable-packages** - Access nixpkgs-unstable via `pkgs.unstable.*`
- **master-packages** - Access nixpkgs-master via `pkgs.master.*`
- **NUR** - Firefox extensions, Coq packages from Nix User Repository
- **nix-vscode-extensions** - VS Code marketplace extensions

Others can use your overlays:
```nix
inputs.your-configs.overlays.unstable-packages
```

### Custom Modules
Exportable modules in `common/modules/nixos/`:
- **common-base** - Shared overlays + nix settings used everywhere
- **server-base** - Base server configuration with overlays
- **users** - Desktop user configuration
- **locale** - Locale and timezone settings
- **secrets** - Secrets management configuration
- **tailscale** - Tailscale VPN configuration
- **disk-config** - Disko disk partitioning

Others can use your modules:
```nix
inputs.your-configs.nixosModules.server-base
```

Register new modules in `common/modules/nixos/default.nix`.

## Troubleshooting / FAQ

### Files don't exist even though they do
Nix flakes only see files tracked by git. Run `git add .` to make them visible. Files in `.gitignore` are invisible to Nix.

### Wrong version of software or can't find new packages
Flake dependencies strictly follow `flake.lock`. Update with:
```bash
nix flake update
```

### Home-manager errors about missing options
If using integrated home-manager (recommended), remove `nixpkgs.config` from `home.nix` - it's inherited from the system configuration.

### Build fails with "path not valid" errors
This can happen after major updates. Try:
```bash
nix flake update
nix-collect-garbage -d
```

## Learning Resources

New to Nix? Check out:
- [NixOS Learn Hub](https://nixos.org/learn.html) - Official guides and manuals
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [Nix Pills](https://nixos.org/guides/nix-pills/) - Deep dive into Nix concepts
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [nixos-facter](https://github.com/numtide/nixos-facter)
- [Disko](https://github.com/nix-community/disko)

## Contributing

Found an issue or have suggestions? Please [open an issue](https://github.com/Wenri/nix-configs/issues)!

## See Also

For more advanced examples, check out:
- [Misterio77's config](https://github.com/misterio77/nix-config) - Original inspiration
- [CLAUDE.md](./CLAUDE.md) - Detailed architecture documentation for Claude Code
