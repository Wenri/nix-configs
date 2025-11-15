{lib, ...}: {
  imports = [
    ./common.nix
  ];

  networking.hostName = "freenix";

  # Optimize Tailscale for this host's primary network interface
  services.tailscale.optimizedInterface = "enp0s8u1";

  # Configure systemd-networkd for enp0s8u1 interface
  # IPv4: DHCP
  # IPv6: Automatic configuration via Router Advertisements
  systemd.network.networks."40-enp0s8u1" = {
    name = "enp0s8u1";
    enable = true;
    
    # Network configuration
    # Explicitly enable DHCPv4 (IPv4 DHCP)
    # IPv6 uses Router Advertisements only
    networkConfig = {
      DHCP = "yes"; # Enable IPv4 DHCP
      IPv6AcceptRA = true; # IPv6 Router Advertisement configuration
    };
  };
}
