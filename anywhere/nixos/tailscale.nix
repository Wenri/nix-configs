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
      description = "List of network interfaces to optimize for Tailscale (enables UDP GRO forwarding). If empty, automatically detects interfaces configured with MAC addresses in systemd-networkd.";
      example = [ "enp0s5" "enp0s8u1" ];
    };
  };

  config = let
    # Extract MAC addresses from systemd-networkd configurations
    # Only include networks that have MAC address matching and IPv6AcceptRA enabled
    networkdMacAddresses = lib.mapAttrsToList (_: netCfg:
      if netCfg.matchConfig ? MACAddress && 
         netCfg.enable == true &&
         (netCfg.networkConfig ? IPv6AcceptRA && netCfg.networkConfig.IPv6AcceptRA == true)
      then netCfg.matchConfig.MACAddress
      else null
    ) config.systemd.network.networks;
    
    # Filter out null values
    optimizedMacAddresses = lib.filter (x: x != null) networkdMacAddresses;
    
    # Use explicitly configured interfaces, or auto-detect from MAC addresses
    optimizedInterfaces = if config.services.tailscale.optimizedInterfaces != [] then
      config.services.tailscale.optimizedInterfaces
    else
      []; # Will match by MAC address instead
  in {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
    };

    # Enable network optimization if interfaces or MAC addresses are specified
    services.networkd-dispatcher = lib.mkIf (optimizedInterfaces != [] || optimizedMacAddresses != []) {
      enable = true;
      rules."50-tailscale" = {
        onState = ["routable"];
        script = ''
          #!${pkgs.runtimeShell}
          set -e
          
          interface="$1"
          
          # Get MAC address of the interface
          interface_mac="$(${pkgs.iproute2}/bin/ip link show "$interface" 2>/dev/null | grep -oP 'link/ether \K[^ ]+' || echo "")"
          
          if [ -z "$interface_mac" ]; then
            exit 0
          fi
          
          # Check if interface name matches explicitly configured interfaces
          ${lib.concatStringsSep "\n" (map (iface: ''
          if [ "$interface" = "${iface}" ]; then
            ${pkgs.ethtool}/bin/ethtool -K "$interface" rx-udp-gro-forwarding on rx-gro-list off
            exit 0
          fi
          '') optimizedInterfaces)}
          
          # Check if MAC address matches auto-detected interfaces
          ${lib.concatStringsSep "\n" (map (mac: ''
          if [ "$interface_mac" = "${mac}" ]; then
            # Set sysctl for IPv6 RA acceptance (needed when forwarding is enabled)
            ${pkgs.procps}/bin/sysctl -w "net.ipv6.conf.$interface.accept_ra=2" >/dev/null 2>&1 || true
            # Apply ethtool optimizations
            ${pkgs.ethtool}/bin/ethtool -K "$interface" rx-udp-gro-forwarding on rx-gro-list off
            exit 0
          fi
          '') optimizedMacAddresses)}
          
          # Interface not in optimized list, skip
          exit 0
        '';
      };
    };

    # Enable IPv6 RA acceptance on Tailscale optimized interfaces even with forwarding enabled
    # Tailscale's useRoutingFeatures enables IPv6 forwarding, which disables RA acceptance by default
    # This allows systemd-networkd to accept Router Advertisements on the optimized interfaces
    # For auto-detected MAC-based interfaces, we'll set accept_ra=2 for all interfaces
    # and let systemd-networkd handle it via IPv6AcceptRA=true in the network config
    boot.kernel.sysctl = lib.mkMerge (
      (map (iface: {
        "net.ipv6.conf.${iface}.accept_ra" = 2;
      }) optimizedInterfaces) ++
      # For MAC-based matching, we need to apply sysctl dynamically
      # Since we can't know interface names at build time, we set a default
      # and the networkd config with IPv6AcceptRA=true will handle it
      []
    );
  };
}
