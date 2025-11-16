# NixOS Configurations (2025 Edition)

**Personal NixOS configurations** featuring unified infrastructure and modern best practices.

> **Note:** This is a personal configuration repository based on [nix-starter-config](https://github.com/Misterio77/nix-starter-config). All configurations share unified infrastructure from `common/` - the same overlays, modules, packages, and userspace are used across WSL, desktop, and server deployments.

This repository contains three NixOS + home-manager configurations with **unified infrastructure**:
- **minimal/** - NixOS-WSL for Windows development
- **standard/** - Desktop environments (GNOME, Plasma6)
- **anywhere/** - Production servers (Matrix, ARM)

Features modern architecture with integrated home-manager, auto-generated configurations, and nixos-anywhere deployment.

## Unified Architecture

**All configurations share infrastructure from `common/`:**
- **Overlays** - NUR (Firefox extensions, Coq packages), vscode-marketplace, unstable/master packages
- **Modules** - Custom NixOS and home-manager modules
- **Packages** - Custom package definitions
- **Home-Manager** - Identical userspace across all environments (all users are the same person)

## What This Provides

### [Minimal](./minimal) - NixOS-WSL Configuration
- **Modern 2025 architecture** with single source of truth (`hosts` attribute)
- **NixOS-WSL** integration for Windows Subsystem for Linux
- **Integrated home-manager** - Single `nixos-rebuild switch` updates both system and user
- **Tailscale** with userspace networking for WSL
- **Unified infrastructure** from `common/` - Same overlays, modules, packages as other configs
- **Status:** ✅ Active WSL configuration with unified userspace

### [Standard](./standard) - Desktop Environments
- **Modern 2025 architecture** with single source of truth (`hosts` attribute)
- **Integrated home-manager** - Single `nixos-rebuild switch` updates both system and user
- **Desktop environments**: GNOME, Plasma6, IRIF with full GUI applications
- **ZFS support** with LUKS encryption
- **VMware guest tools** integration
- **Unified infrastructure** from `common/` - Shares all overlays, modules, packages
- **Development environments**: Coq, Haskell, LaTeX, Python, Typst
- **Status:** ✅ Production desktop configurations

### [Anywhere](./anywhere) - Production Servers
- **Modern 2025 flake architecture** - Single source of truth with auto-generated configurations
- **Integrated home-manager** - Single command updates both system and user environment
- **Modular architecture** - Separate modules for services (tailscale, synapse, users)
- **nixos-anywhere support** - Remote installation and deployment
- **nixos-facter** - Modern hardware detection (no `hardware-configuration.nix`)
- **Disko** - Declarative disk partitioning
- **Production servers**: Matrix (x86_64), Freenix (aarch64)
- **Unified infrastructure** from `common/` - Shares all overlays, modules, packages
- **Status:** ✅ Battle-tested production configurations

## Modern Architecture (2025)

All three configurations (`minimal/`, `standard/`, `anywhere/`) follow modernized patterns and share unified infrastructure:

### Unified Infrastructure (`common/`)

**All configurations share the same infrastructure:**

```
common/
├── overlays/           # Package overlays exported by all flakes
│   └── default.nix    # NUR, vscode-marketplace, unstable, master packages
├── modules/           # Shared modules
│   ├── nixos/        # Custom NixOS modules
│   └── home-manager/ # Custom home-manager modules
├── pkgs/             # Custom packages accessible from all flakes
│   └── default.nix   # Package definitions
└── home-manager/     # Unified userspace configuration
    ├── default.nix           # Auto-imported core modules
    ├── base-packages.nix     # Essential CLI tools
    ├── git.nix              # Git config with 1Password signing
    ├── zsh.nix              # Zsh with oh-my-zsh
    ├── ssh.nix              # SSH with 1Password agent
    ├── gh.nix               # GitHub CLI
    ├── programs.nix         # Base program enables
    ├── desktop-packages.nix # GUI applications (optional)
    ├── development/         # Dev environments (optional)
    └── programs/            # Desktop programs (optional)
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

### Which Configuration to Use?

This is a personal configuration repository with unified infrastructure. All configurations share:
- **Same userspace** - Identical packages, programs, and dotfiles
- **Same overlays** - NUR extensions, vscode-marketplace, unstable packages
- **Same modules** - Custom NixOS and home-manager modules

Choose based on deployment target:
- **minimal/** - For NixOS-WSL on Windows
- **standard/** - For desktop machines with GUI (GNOME/Plasma6)
- **anywhere/** - For production servers (Matrix, ARM servers)

### Customization

Since all configurations share `common/`, you can customize once and benefit everywhere:

1. **Update user details** in `common/home-manager/git.nix`:
   - User name and email
   - SSH signing key

2. **Add packages** in `common/home-manager/`:
   - `base-packages.nix` - CLI tools (applies to all configs)
   - `desktop-packages.nix` - GUI apps (applies to standard/)

3. **Configure programs** in `common/home-manager/programs/`:
   - Firefox extensions, VS Code settings, etc.

4. **Per-configuration customization:**
   - Update `defaultUsername` in each `flake.nix`
   - Add/modify hosts in the `hosts` attribute set
   - Edit host-specific configs in `nixos/`
   - Update `users.nix` with your SSH keys

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
sudo nixos-rebuild switch --flake .#hostname

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
home-manager switch --flake .#username@hostname

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
├── common/              # Unified infrastructure (shared by all configs)
│   ├── overlays/       # NUR, vscode-marketplace, unstable packages
│   ├── modules/        # Custom NixOS and home-manager modules
│   ├── pkgs/           # Custom package definitions
│   └── home-manager/   # Unified userspace (packages, programs, dev envs)
├── anywhere/           # Production servers
│   ├── flake.nix      # Exports from ../common/, hosts-based config
│   ├── nixos/
│   │   ├── common.nix       # Base config with common overlays
│   │   ├── host-matrix.nix  # Matrix server (x86_64)
│   │   ├── host-freenix.nix # ARM server (aarch64)
│   │   ├── disk-config.nix  # Disko partitioning
│   │   ├── users.nix        # User accounts
│   │   ├── tailscale.nix    # VPN module
│   │   ├── synapse.nix      # Matrix server
│   │   └── facter-*.json    # Hardware detection
│   └── home-manager/
│       └── home.nix         # Imports common modules only
├── minimal/            # NixOS-WSL
│   ├── flake.nix      # Exports from ../common/, NixOS-WSL integration
│   ├── nixos/
│   │   ├── common.nix       # WSL config with common overlays
│   │   └── users.nix        # User accounts
│   └── home-manager/
│       └── home.nix         # Imports common modules only
└── standard/           # Desktop environments
    ├── flake.nix      # Exports from ../common/, desktop-focused
    ├── nixos/
    │   ├── configuration-nixos-gnome.nix   # GNOME desktop
    │   ├── configuration-nixos-plasma6.nix # Plasma6 desktop
    │   ├── configuration-irif.nix          # IRIF config
    │   └── hardware-configuration-*.nix     # Hardware configs
    └── home-manager/
        └── home.nix   # Imports common + desktop + development + programs
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
All custom packages are defined in `common/pkgs/` and exported by all three flakes:
```bash
# Build your package from any configuration
nix build ./anywhere#package-name
nix build ./minimal#package-name
nix build ./standard#package-name

# Use in shell
nix shell ./anywhere#package-name
```

Create a folder under `common/pkgs/` with a `default.nix` - it's automatically available in all configurations.

### Overlays
All overlays are defined in `common/overlays/default.nix` and used by all configurations:
- **additions** - Custom packages from `common/pkgs/`
- **modifications** - Package patches (e.g., fcitx5-rime-lua with Lua support)
- **unstable-packages** - Access nixpkgs-unstable via `pkgs.unstable.*`
- **master-packages** - Access nixpkgs-master via `pkgs.master.*`
- **NUR** - Firefox extensions, Coq packages from Nix User Repository
- **nix-vscode-extensions** - VS Code marketplace extensions

### Custom Modules
Create reusable abstractions in `common/modules/nixos/` or `common/modules/home-manager/`. Register them in respective `default.nix` files. All modules are automatically available in all configurations.

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
