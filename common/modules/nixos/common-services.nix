{
  lib,
  ...
}: {
  services.openssh = {
    enable = lib.mkDefault true;
    startWhenNeeded = lib.mkDefault false;
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
    };
  };

  services.tailscale.enable = lib.mkDefault true;
}
