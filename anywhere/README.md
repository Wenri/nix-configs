# Modular NixOS Configuration Template

This is a production-ready, modular NixOS configuration template featuring:

- **Modern 2025 flake architecture** - Single source of truth with auto-generated configurations
- **Integrated home-manager** - Single command updates both system and user environment
- **Modular architecture** - Separate modules for different services (tailscale, synapse, users)
- **Common base config** - Shared configuration in `common.nix` to reduce duplication
- **Host-specific configs** - Clean host configs that only specify what's unique
- **nixos-anywhere support** - Remote installation via nixos-anywhere
- **nixos-facter** - Modern hardware detection instead of traditional hardware-configuration.nix
- **Disko** - Declarative disk partitioning

## Structure

```
flake.nix                # Modern flake with hosts-based configuration
├── hosts = { freenix, matrix }  # Single source of truth
├── nixosConfigurations  # Auto-generated from hosts
└── homeConfigurations   # Auto-generated from hosts

nixos/
├── common.nix           # Shared base configuration for all systems
├── host-matrix.nix      # Matrix server host configuration
├── host-freenix.nix     # Freenix host configuration
├── disk-config.nix      # Disko disk partitioning
├── users.nix            # User accounts, permissions, and user programs (uses username variable)
├── tailscale.nix        # Tailscale VPN module with network optimization
├── synapse.nix          # Matrix Synapse server module (uses hostname variable)
└── facter-*.json        # Hardware detection from nixos-facter (pattern: facter-${hostname}.json)

home-manager/
├── home.nix             # Home-manager configuration (integrated into NixOS)
├── packages.nix         # User packages (includes jq)
└── programs/            # Program-specific configs
    ├── default.nix      # Program imports
    ├── git.nix          # Git configuration (synced with GitHub)
    ├── gh.nix           # GitHub CLI configuration
    ├── ssh.nix          # SSH configuration
    └── zsh.nix          # Zsh shell configuration
```

## Quick Start

### Using this template

```bash
nix flake init -t github:Wenri/nix-configs#modular
```

### Customizing

1. **Update flake.nix**:
   - Modify `defaultUsername` variable (default: "wenri")
   - Add/remove hosts in the `hosts` attribute set
   - Configurations are auto-generated from `hosts`

2. **Edit host-*.nix files**:
   - Create new `host-yourhostname.nix` for your host
   - Configure network interfaces, services, etc.
   - Hostname is automatically set from `hostname` variable

3. **Edit users.nix**:
   - User account is created using `username` variable
   - Add SSH keys
   - Configure sudo/permissions

4. **Update home-manager/packages.nix**:
   - Add your user packages
   - nixpkgs config is inherited from system

5. **Configure GitHub CLI** (optional):
   - Run `gh auth login` to authenticate
   - Git config will be automatically synced with GitHub profile
   - See `programs/git.nix` for configuration

### Building

```bash
# Single command updates both NixOS system and home-manager
sudo nixos-rebuild switch --flake .#hostname

# Standalone home-manager also available (backward compatibility)
home-manager switch --flake .#username@hostname
```

### Remote deployment with nixos-anywhere

```bash
# Pattern: nixos-anywhere --flake .#<hostname> --generate-hardware-config nixos-facter ./nixos/facter-<hostname>.json <target>
nixos-anywhere --flake .#matrix \
  --generate-hardware-config nixos-facter ./nixos/facter-matrix.json \
  root@target-host
```

## Features

### Modular Design

Each service/concern is in its own module:
- **tailscale.nix** - VPN with custom `optimizedInterface` option
- **synapse.nix** - Matrix server (optional)
- **users.nix** - All user-related configuration
- **common.nix** - System infrastructure only

### Host-Specific Configs

Host configs (`host-*.nix`) are minimal and only specify:
- Hostname
- Service-specific parameters (like Tailscale interface)
- Optional module imports (like synapse.nix)

### Passwordless Sudo

Configured for wheel group members (disable in users.nix if not desired).

### System Tools Included

- ethtool, usbutils (lsusb)
- curl, git, vim, wget
- jq (JSON processor)
- ndisc6 (IPv6 discovery)
- iputils (ping, ping6)

### Memory Management

- 2GB file-based swap
- zram with zstd compression (30% of RAM)
- systemd-oomd for OOM protection

### Modern Architecture

- **Single source of truth** - `hosts` attribute set defines all configurations
- **Auto-generation** - nixosConfigurations and homeConfigurations generated via `lib.mapAttrs`
- **Variable system** - `username` and `hostname` passed through specialArgs
- **Integrated home-manager** - No separate command needed
- **Proper packages** - Uses `mkPkgs` helper instead of legacyPackages

## Customization

### Adding a new host

**Modern approach** - Just add one entry to `flake.nix`:

```nix
# In flake.nix
hosts = {
  freenix = { system = "aarch64-linux"; };
  matrix = { system = "x86_64-linux"; };
  newhost = { system = "x86_64-linux"; };  # ← Add this
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

That's it! This automatically creates:
- `nixosConfigurations.newhost`
- `homeConfigurations."wenri@newhost"`
- Facter file path: `./nixos/facter-newhost.json`

No manual flake.nix configuration needed!

### Disabling a module

Simply remove the import from `common.nix` or the host config. For example, to disable Tailscale:

```nix
# In common.nix, remove:
# ./tailscale.nix
```

### Adding a new module

1. Create `nixos/myservice.nix`:
```nix
{pkgs, lib, config, ...}: {
  options = {
    services.myservice.enable = lib.mkEnableOption "My Service";
  };

  config = lib.mkIf config.services.myservice.enable {
    # Your service configuration
  };
}
```

2. Import in `common.nix` or a host config:
```nix
imports = [
  # ...
  ./myservice.nix
];
```

## See Also

- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere)
- [nixos-facter](https://github.com/numtide/nixos-facter)
- [Disko](https://github.com/nix-community/disko)
