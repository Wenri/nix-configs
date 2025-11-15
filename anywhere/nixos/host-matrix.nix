{...}: {
  imports = [
    ./common.nix
    ./synapse.nix
  ];

  # Optimize Tailscale for this host's primary network interface
  services.tailscale.optimizedInterface = "ens3";

  # Configure static IPv6 address
  networking.interfaces.ens3.ipv6.addresses = [
    {
      address = "2a0f:ca80:1337:0000:0000:0000:4053:872d";
      prefixLength = 64;
    }
  ];

  # Configure default IPv6 route via discovered router
  # Router: fe80::204b:cdff:fe8f:319 (MAC: 6c:3b:e5:b9:51:50)
  # Note: This is NOT the IPv4 gateway (93.123.118.1). The network appears to have
  # separate IPv4 and IPv6 gateways. The IPv4 gateway doesn't route IPv6 traffic,
  # but this device (fe80::204b:cdff:fe8f:319) is marked as "router" in the
  # neighbor table and successfully routes IPv6 traffic to the internet.
  networking.interfaces.ens3.ipv6.routes = [
    {
      address = "::";
      prefixLength = 0;
      via = "fe80::204b:cdff:fe8f:319";
    }
  ];
}
