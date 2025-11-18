{
  lib,
  hostname,
  ...
}: {
  imports = [
    ./common-base.nix
    ./tailscale.nix
  ];

  wsl.enable = lib.mkDefault true;

  networking.hostName = lib.mkDefault hostname;

  services.openssh = {
    startWhenNeeded = lib.mkForce true;
  };
  systemd.sockets.sshd.socketConfig = lib.mkDefault {
    ListenStream = ["/run/sshd.sock"];
    SocketMode = "0600";
  };
}
