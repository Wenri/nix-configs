{
  pkgs,
  config,
  lib,
  hostname,
  ...
}: {
  imports = [
    ./common.nix
    ./synapse.nix
  ];

  # Configure systemd-networkd for ens3 interface
  # Tailscale optimization will be auto-detected if MAC address matching is configured
  # Match by MAC address for stability (interface names can change)
  # IPv4: DHCP
  # IPv6: Static address + automatic router discovery via Router Advertisements
  systemd.network.networks."40-ens3" = {
    matchConfig = {
      MACAddress = "00:16:3e:4f:ac:bb"; # ens3
    };
    enable = true;
    
    # Network configuration
    # Explicitly enable DHCPv4 (IPv4 DHCP)
    # IPv6 uses static address + Router Advertisements
    networkConfig = {
      DHCP = "yes"; # Enable IPv4 DHCP
      IPv6AcceptRA = true; # Accept RAs even with forwarding enabled (for Tailscale)
    };
    
    # IPv6 static address configuration
    addresses = [
      {
        Address = "2a0f:ca80:1337::4053:872d/64";
      }
    ];
    
    # IPv6 default route via discovered router
    # Router doesn't send Router Advertisements, so we configure static route
    # Router: fe80::204b:cdff:fe8f:319 (discovered via neighbor table)
    routes = [
      {
        Destination = "::/0";
        Gateway = "fe80::204b:cdff:fe8f:319";
        GatewayOnLink = true; # Required for link-local gateway
      }
    ];
  };
}
