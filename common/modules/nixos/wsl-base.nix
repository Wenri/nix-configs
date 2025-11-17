{
  lib,
  hostname,
  ...
}: {
  imports = [./common-base.nix];

  wsl.enable = lib.mkDefault true;

  networking.hostName = lib.mkDefault hostname;

  services.openssh = {
    enable = lib.mkDefault true;
    startWhenNeeded = lib.mkDefault true;
  };
  systemd.sockets.sshd.socketConfig = lib.mkDefault {
    ListenStream = ["/run/sshd.sock"];
    SocketMode = "0600";
  };
}
