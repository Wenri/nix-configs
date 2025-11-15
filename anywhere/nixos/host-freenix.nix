{lib, ...}: {
  imports = [
    ./common.nix
  ];

  networking.hostName = "freenix";

  # Optimize Tailscale for both network interfaces
  services.tailscale.optimizedInterfaces = [ "enp0s5" "enp0s8u1" ];

  # Configure systemd-networkd for both network interfaces
  # Match by MAC address for stability (interface names can change)
  # IPv4: DHCP
  # IPv6: Automatic configuration via Router Advertisements
  systemd.network.networks."40-enp0s5" = {
    matchConfig = {
      MACAddress = "9e:c4:c5:11:3a:96"; # enp0s5
    };
    enable = true;
    networkConfig = {
      DHCP = "yes"; # Enable IPv4 DHCP
      IPv6AcceptRA = true; # IPv6 Router Advertisement configuration
    };
  };

  systemd.network.networks."40-enp0s8u1" = {
    matchConfig = {
      MACAddress = "2c:16:db:a1:3b:e5"; # enp0s8u1
    };
    enable = true;
    networkConfig = {
      DHCP = "yes"; # Enable IPv4 DHCP
      IPv6AcceptRA = true; # IPv6 Router Advertisement configuration
    };
  };
}
