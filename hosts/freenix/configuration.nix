{
  lib,
  hostname,
  outputs,
  ...
}: {
    imports = [
      outputs.nixosModules.server-base
      outputs.nixosModules.users
      outputs.nixosModules.netclient
    ];

  networking.hostName = hostname;

  # Configure systemd-networkd for both network interfaces
  # Tailscale optimization will be auto-detected based on MAC addresses below
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

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
