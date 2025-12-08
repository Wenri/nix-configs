{
  lib,
  pkgs,
  username,
  ...
}: let
  keys = import ../../keys.nix;
in {
  users.users = {
    ${username} = lib.mkMerge [
      {
        isNormalUser = true;
        description = "Bingchen Gong";
        openssh.authorizedKeys.keys = keys.all;
        extraGroups = ["wheel"];
        packages = with pkgs; [
          # thunderbird
        ];
        shell = pkgs.zsh;
      }
    ];

    root.openssh.authorizedKeys.keys = keys.all;
  };

  programs.zsh.enable = true;
  programs.firefox.enable = true;
  programs.iftop.enable = true;
  services.printing.browsed.enable = false;

  security.sudo.wheelNeedsPassword = lib.mkDefault false;

  services.tailscale.extraUpFlags = lib.mkAfter ["--operator=${username}"];
}
