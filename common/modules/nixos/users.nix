{
  lib,
  pkgs,
  username,
  ...
}: {
  users.users = {
    ${username} = lib.mkMerge [
      {
        isNormalUser = true;
        description = "Bingchen Gong";
        openssh.authorizedKeys.keys = [
          # TODO: Add your SSH public key(s) here, if you plan on using SSH to connect
        ];
        extraGroups = ["wheel"];
        packages = with pkgs; [
          # thunderbird
        ];
        shell = pkgs.zsh;
      }
    ];

    root.openssh.authorizedKeys.keys = [
      # TODO: Add your SSH public key(s) here for root access
    ];
  };

  programs.zsh.enable = true;
  programs.firefox.enable = true;
  programs.iftop.enable = true;
  services.printing.browsed.enable = false;

  security.sudo.wheelNeedsPassword = lib.mkDefault false;

  services.tailscale.extraUpFlags = lib.mkAfter ["--operator=${username}"];
}
