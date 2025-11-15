{lib, ...}: {
  imports = [
    ./common.nix
  ];

  networking.hostName = "freenix";

  # Optimize Tailscale for this host's primary network interface
  services.tailscale.optimizedInterface = "enp0s3";

  # Configure systemd-networkd for enp0s3 interface
  # IPv4: DHCP
  # IPv6: Automatic configuration via Router Advertisements
  systemd.network.networks."40-enp0s3" = {
    name = "enp0s3";
    enable = true;
    
    # Network configuration
    # DHCP = "yes" (useNetworkd default) - enables IPv4 DHCP
    # Since network doesn't provide DHCPv6, this won't cause conflicts
    # IPv6 uses Router Advertisements only
    networkConfig = {
      IPv6AcceptRA = true; # IPv6 Router Advertisement configuration
    };
  };
}
