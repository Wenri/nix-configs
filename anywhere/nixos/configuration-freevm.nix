{pkgs, ...}: {
  imports = [
    ./common.nix
  ];

  networking.hostName = "freenix";

  services.networkd-dispatcher = {
    enable = true;
    rules."50-tailscale" = {
      onState = ["routable"];
      script = ''
        #!${pkgs.runtimeShell}
        ${pkgs.ethtool}/bin/ethtool -K enp0s3 rx-udp-gro-forwarding on rx-gro-list off
      '';
    };
  };
}
