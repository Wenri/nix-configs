{
  lib,
  pkgs,
  username,
  ...
}: {
  users.users.${username} = {
    isNormalUser = true;
    description = "Bingchen Gong";
    openssh.authorizedKeys.keys = [
      # TODO: Add your SSH public key(s) here, if you plan on using SSH to connect
    ];
    extraGroups = ["networkmanager" "wheel"];
    packages = with pkgs; [
      # thunderbird
    ];
    shell = pkgs.zsh;
  };

  programs.zsh.enable = true;
  programs.firefox.enable = true;
  programs.iftop.enable = true;
  services.printing.browsed.enable = false;

  services.tailscale.extraUpFlags = lib.mkAfter ["--operator=${username}"];
}
