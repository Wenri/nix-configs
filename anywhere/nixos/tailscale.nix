{
  lib,
  pkgs,
  config,
  ...
}: {
  options = {
    services.tailscale.optimizedInterface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Network interface to optimize for Tailscale (enables UDP GRO forwarding)";
    };
  };

  config = {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
    };

    # Enable network optimization if interface is specified
    services.networkd-dispatcher = lib.mkIf (config.services.tailscale.optimizedInterface != null) {
      enable = true;
      rules."50-tailscale" = {
        onState = ["routable"];
        script = ''
          #!${pkgs.runtimeShell}
          ${pkgs.ethtool}/bin/ethtool -K ${config.services.tailscale.optimizedInterface} rx-udp-gro-forwarding on rx-gro-list off
        '';
      };
    };

    # Enable IPv6 RA acceptance on Tailscale optimized interface even with forwarding enabled
    # Tailscale's useRoutingFeatures enables IPv6 forwarding, which disables RA acceptance by default
    # This allows systemd-networkd to accept Router Advertisements on the optimized interface
    boot.kernel.sysctl = lib.mkIf (config.services.tailscale.optimizedInterface != null) {
      "net.ipv6.conf.${config.services.tailscale.optimizedInterface}.accept_ra" = 2;
    };
  };
}
