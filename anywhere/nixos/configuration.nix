{pkgs, ...}: {
  imports = [
    ./common.nix
    ./synapse.nix
  ];

  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = ["routable"];
      script = ''
        #!${pkgs.runtimeShell}
        ${pkgs.ethtool}/bin/ethtool -K ens3 rx-udp-gro-forwarding on rx-gro-list off
      '';
    };
  };
}
