{
  pkgs,
  config,
  lib,
  hostname,
  outputs,
  ...
}: {
    imports = [
      outputs.nixosModules.server-base
      outputs.nixosModules.users
      outputs.nixosModules.netclient
      ./synapse.nix
    ];

  # Use Xanmod kernel for better performance
  boot.kernelPackages = pkgs.linuxPackages_xanmod_latest;

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
    # Router: 2a0f:ca80:1337::1 (lladdr 84:c1:c1:81:c1:30, same device as IPv4 gateway 93.123.118.1)
    routes = [
      {
        Destination = "::/0";
        Gateway = "2a0f:ca80:1337::1";
        GatewayOnLink = true; # Required since gateway is on-link but not in routing table
      }
    ];
  };

  # ext4 performance: writeback mode skips data journaling, async commit reduces sync overhead
  fileSystems."/".options = lib.mkAfter [
    "data=writeback"
    "journal_async_commit"
  ];

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
