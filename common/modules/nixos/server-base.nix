{
  modulesPath,
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./common-base.nix
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
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
}
