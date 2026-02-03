{lib, pkgs, ...}: {
  # Netmaker mesh VPN client
  services.netclient.enable = lib.mkDefault true;
  environment.systemPackages = [pkgs.wireguard-tools];

  # WireGuard tunnel port
  networking.firewall.allowedUDPPorts = [51821];

  # Trust all traffic over the Netmaker interface
  networking.firewall.trustedInterfaces = ["netmaker"];
}
