# Modular NixOS Configuration Template

This is a production-ready, modular NixOS configuration template featuring:

- **Modular architecture** - Separate modules for different services (tailscale, synapse, users)
- **Common base config** - Shared configuration in `common.nix` to reduce duplication
- **Host-specific configs** - Clean host configs that only specify what's unique
- **nixos-anywhere support** - Remote installation via nixos-anywhere
- **nixos-facter** - Modern hardware detection instead of traditional hardware-configuration.nix
- **Disko** - Declarative disk partitioning

## Structure

```
nixos/
├── common.nix           # Shared base configuration for all systems
├── host-generic.nix     # Generic host configuration
├── host-freenix.nix     # Specific host configuration example
├── disk-config.nix      # Disko disk partitioning
├── users.nix            # User accounts, permissions, and user programs
├── tailscale.nix        # Tailscale VPN module with network optimization
├── synapse.nix          # Matrix Synapse server module (optional)
└── facter*.json         # Hardware detection from nixos-facter

home-manager/
├── home.nix             # Home-manager configuration
├── packages.nix         # User packages
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
   - Modify NixOS configuration names
   - Update home-manager usernames and hostnames

2. **Edit host-*.nix files**:
   - Set your hostname
   - Configure Tailscale interface (if using)

3. **Edit users.nix**:
   - Update user details
   - Add SSH keys
   - Configure sudo/permissions

4. **Update home-manager/home.nix**:
   - Set your username and home directory
   - Add your packages in packages.nix

5. **Configure GitHub CLI** (optional):
   - Run `gh auth login` to authenticate
   - Git config will be automatically synced with GitHub profile
   - See `programs/git.nix` for configuration

### Building

```bash
# NixOS system
sudo nixos-rebuild switch --flake .#hostname

# Home-manager
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

- ethtool
- usbutils (lsusb)
- curl, git, vim, wget

### Memory Management

- 2GB file-based swap
- zram with zstd compression (30% of RAM)
- systemd-oomd for OOM protection

## Customization

### Adding a new host

1. Create `nixos/host-newhost.nix`:
```nix
{...}: {
  imports = [
    ./common.nix
  ];

  networking.hostName = "newhost";
  services.tailscale.optimizedInterface = "eth0";
}
```

2. Add to `flake.nix`:
```nix
nixosConfigurations.newhost = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = {inherit inputs outputs;};
  modules = [
    disko.nixosModules.disko
    ./nixos/host-newhost.nix
    nixos-facter-modules.nixosModules.facter
    # ... facter config
  ];
};
```

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
