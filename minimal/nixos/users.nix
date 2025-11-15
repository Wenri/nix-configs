{
  pkgs,
  username,
  ...
}: {
  users.users = {
    ${username} = {
      # You can set an initial password for your user.
      # Be sure to change it (using passwd) after rebooting!
      initialPassword = "nixos";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        # TODO: Add your SSH public key(s) here, if you plan on using SSH to connect
      ];
      description = "NixOS User";
      extraGroups = ["wheel"];
      shell = pkgs.zsh;
    };

    root = {
      openssh.authorizedKeys.keys = [
        # TODO: Add your SSH public key(s) here for root access
      ];
    };
  };

  # Enable passwordless sudo for wheel group
  security.sudo.wheelNeedsPassword = false;

  programs.zsh.enable = true;
}
