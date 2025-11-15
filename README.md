# NixOS Starter Configs (2025 Edition)

**Modernized and production-ready** NixOS flake templates featuring the latest best practices.

This repository contains multiple NixOS + home-manager flake templates, from minimal starter configs to production-ready modular architectures with modern features like integrated home-manager, auto-generated configurations, and nixos-anywhere deployment.

## What This Provides

### [Minimal](./minimal) - Getting Started
- Basic NixOS configuration on `nixos/configuration.nix`
- Home-manager configuration on `home-manager/home.nix`
- Perfect for first-time flake users or simple migrations
- **Status:** Template starter

### [Standard](./standard) - Extended Template
- **Modern 2025 architecture** with single source of truth (`hosts` attribute)
- **Integrated home-manager** - Single `nixos-rebuild switch` updates both system and user
- Custom packages under `pkgs/` - Build with `nix build .#package-name`
- Overlays for package modifications and unstable packages
- Reusable NixOS modules (`modules/nixos/`) and home-manager modules (`modules/home-manager/`)
- Desktop environments: GNOME, Plasma6, IRIF
- Auto-generated configurations from `hosts` attribute set
- **Status:** ✅ Modernized with 2025 best practices

### [Anywhere](./anywhere) - Production Modular Architecture
- **Modern 2025 flake architecture** - Single source of truth with auto-generated configurations
- **Integrated home-manager** - Single command updates both system and user environment
- **Modular architecture** - Separate modules for services (tailscale, synapse, users)
- **Common base config** - Shared `common.nix` to reduce duplication
- **nixos-anywhere support** - Remote installation and deployment
- **nixos-facter** - Modern hardware detection (no `hardware-configuration.nix`)
- **Disko** - Declarative disk partitioning
- **Production-ready** servers: Matrix (matrix), ARM server (freenix)
- **Status:** ✅ Fully modernized, battle-tested production configs

## Modern Architecture (2025)

Both `standard/` and `anywhere/` now follow modernized patterns:

### Single Source of Truth
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

### Which Template to Choose?

- **Minimal**: First time with flakes, or simple configuration migration
- **Standard**: Need custom packages, overlays, desktop environment
- **Anywhere**: Production deployments, remote servers, modular architecture

### Setup Steps

1. **Create your config repository:**
```bash
cd ~/Documents
git init nix-config
cd nix-config
```

2. **Enable flakes (if not already enabled):**
```bash
# Check Nix version (should be 2.4+)
nix --version

# Enable experimental features
export NIX_CONFIG="experimental-features = nix-command flakes"
```

3. **Get the template:**
```bash
# Minimal version
nix flake init -t github:Wenri/nix-configs#minimal

# Standard version (recommended for desktops)
nix flake init -t github:Wenri/nix-configs#standard

# Anywhere/modular version (recommended for servers)
nix flake init -t github:Wenri/nix-configs#modular
```

4. **For standard/ or anywhere/, customize:**
   - Update `defaultUsername` in `flake.nix`
   - Add/modify hosts in the `hosts` attribute set
   - Edit host-specific configs in `nixos/host-*.nix`
   - Update `users.nix` with your SSH keys and permissions
   - Add packages in `home-manager/packages.nix`

5. **Update flake inputs:**
```bash
nix flake update
```

6. **Git add your changes:**
```bash
git add .
git push  # Or copy somewhere safe if on live medium
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

## Anywhere/Modular Template Details

### Structure
```
anywhere/
├── flake.nix            # Modern flake with hosts-based config
├── nixos/
│   ├── common.nix       # Shared base configuration
│   ├── host-matrix.nix  # Matrix server configuration
│   ├── host-freenix.nix # Freenix server configuration
│   ├── disk-config.nix  # Disko disk partitioning
│   ├── users.nix        # User accounts (uses username variable)
│   ├── tailscale.nix    # Tailscale VPN module
│   ├── synapse.nix      # Matrix Synapse server
│   └── facter-*.json    # Hardware detection (facter-${hostname}.json)
└── home-manager/
    ├── home.nix         # Integrated home-manager config
    ├── packages.nix     # User packages (jq, tmux, etc.)
    └── programs/        # Program-specific configs (git, ssh, zsh)
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

### Custom Packages (standard/)
Create a folder under `pkgs/` with a `default.nix`:
```bash
# Build your package
nix build .#package-name

# Use in shell
nix shell .#package-name
```

### Overlays
Use `overlays/default.nix` to patch or override nixpkgs packages. Keep patch files in `overlays/` folder.

### Custom Modules
Create reusable abstractions in `modules/nixos/` or `modules/home-manager/`. Register them in respective `default.nix` files.

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
