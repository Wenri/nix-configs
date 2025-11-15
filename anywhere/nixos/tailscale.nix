{
  lib,
  pkgs,
  config,
  ...
}: {
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
  in {
    services.tailscale = {
      enable = true;
      useRoutingFeatures = "server";
    };

    # Enable network optimization if MAC addresses are detected
    services.networkd-dispatcher = lib.mkIf (optimizedMacAddresses != []) {
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

    # IPv6 RA acceptance is set dynamically by networkd-dispatcher script
    # when interfaces become routable, since we match by MAC address
    # and interface names are not known at build time
  };
}
