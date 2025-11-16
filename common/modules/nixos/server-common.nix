{
  inputs,
  outputs,
  modulesPath,
  lib,
  config,
  pkgs,
  ...
}: {
  nixpkgs = {
    # Add overlays for NUR, vscode-marketplace, and custom packages
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
      outputs.overlays.master-packages
      inputs.nur.overlays.default
      inputs.nix-vscode-extensions.overlays.default
    ];
    config.allowUnfree = true;
  };

  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Opinionated: disable global registry
      flake-registry = "";
      # Workaround for https://github.com/NixOS/nix/issues/9574
      nix-path = config.nix.nixPath;
    };
    # Opinionated: disable channels
    channel.enable = false;

    # Opinionated: make flake registry and nix path match flake inputs
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    outputs.nixosModules.disk-config
  ];

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    # devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # Enable systemd-networkd for all machines
  # This provides modern network management with automatic IPv6 router discovery
  # networking.useNetworkd enables networkd and automatically disables dhcpcd
  networking.useNetworkd = true;

  services.openssh.enable = true;
  # Enable QEMU guest tools for all machines (applies to both matrix and freenix)
  # This provides qemu-guest-agent and optimizations for running in QEMU/KVM
  services.qemuGuest.enable = true;
  
  # Enable fail2ban for all machines to protect against brute force attacks
  services.fail2ban = {
    enable = true;
    
    # IP addresses/subnets to ignore (never ban)
    # Tailscale uses 100.64.0.0/10 (CGNAT range) for its network
    ignoreIP = [
      "100.64.0.0/10"  # Tailscale IPv4 subnet
    ];
    
    # Configure jails
    jails = {
      # SSH protection - most important for remote servers
      sshd = {
        settings = {
          filter = "sshd";
          maxretry = 5;
          bantime = 3600;  # 1 hour
          findtime = 600;  # 10 minutes
        };
      };
      
      # Protect against repeated authentication failures
      recidive = {
        settings = {
          filter = "recidive";
          action = "%(action_)s";
          bantime = 604800;  # 1 week
          findtime = 86400;   # 1 day
          maxretry = 5;
        };
      };
    };
  };
  
  services.resolved.enable = true;

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.vim
    pkgs.wget
    pkgs.ethtool
    pkgs.usbutils
    pkgs.ndisc6  # IPv6 router discovery tool (rdisc6)
    pkgs.iputils # IPv6 ping tool (ping -6)
    # Create ping6 wrapper for compatibility
    (pkgs.writeShellScriptBin "ping6" ''
      exec ${pkgs.iputils}/bin/ping -6 "$@"
    '')
  ];

  swapDevices = [
    { device = "/swapfile"; size = 2 * 1024; }
  ];

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 30;
  };

  virtualisation.docker.enable = true;

  # Enable systemd-oomd for OOM handling
  systemd.oomd.enable = true;

  system.stateVersion = "25.05";
}
