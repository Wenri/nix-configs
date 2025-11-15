{pkgs, config, lib, ...}: {
  imports = [
    ./common.nix
    ./synapse.nix
  ];

  # Optimize Tailscale for this host's primary network interface
  services.tailscale.optimizedInterface = "ens3";

  # Configure systemd-networkd for ens3 interface
  # IPv4: DHCP
  # IPv6: Static address + automatic router discovery via Router Advertisements
  systemd.network.networks."40-ens3" = {
    name = "ens3";
    enable = true;
    
    # Network configuration
    # DHCP = "yes" (useNetworkd default) - enables IPv4 DHCP
    # Since network doesn't provide DHCPv6, this won't cause conflicts
    # IPv6 uses static address + Router Advertisements
    networkConfig = {
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
