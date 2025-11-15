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
  # Using link-local address fe80::204b:cdff:fe8f:319
  # Note: Link-local routes need to be added via a post-up script
  networking.interfaces.ens3.ipv6.routes = [
    {
      address = "::";
      prefixLength = 0;
      via = "fe80::204b:cdff:fe8f:319";
    }
  ];
}
