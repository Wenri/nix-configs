{
  lib,
  pkgs,
  config,
  ...
}: {
  options = {
    services.tailscale.optimizedInterfaces = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "List of network interfaces to optimize for Tailscale (enables UDP GRO forwarding)";
      example = [ "enp0s5" "enp0s8u1" ];
    };
  };

  config = let
    optimizedInterfaces = config.services.tailscale.optimizedInterfaces;
  in {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
    };

    # Enable network optimization if interfaces are specified
    services.networkd-dispatcher = lib.mkIf (optimizedInterfaces != []) {
      enable = true;
      rules."50-tailscale" = {
        onState = ["routable"];
        script = ''
          #!${pkgs.runtimeShell}
          set -e
          
          interface="$1"
          
          # Check if the current interface is in the optimized list
          ${lib.concatStringsSep "\n" (map (iface: ''
          if [ "$interface" = "${iface}" ]; then
            ${pkgs.ethtool}/bin/ethtool -K "$interface" rx-udp-gro-forwarding on rx-gro-list off
            exit 0
          fi
          '') optimizedInterfaces)}
          
          # Interface not in optimized list, skip
          exit 0
        '';
      };
    };

    # Enable IPv6 RA acceptance on Tailscale optimized interfaces even with forwarding enabled
    # Tailscale's useRoutingFeatures enables IPv6 forwarding, which disables RA acceptance by default
    # This allows systemd-networkd to accept Router Advertisements on the optimized interfaces
    boot.kernel.sysctl = lib.mkMerge (
      map (iface: {
        "net.ipv6.conf.${iface}.accept_ra" = 2;
      }) optimizedInterfaces
    );
  };
}
