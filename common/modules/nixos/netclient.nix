{lib, ...}: {
  # Netmaker mesh VPN client
  services.netclient.enable = lib.mkDefault true;

  # WireGuard tunnel port
  networking.firewall.allowedUDPPorts = [51821];

  # Trust all traffic over the Netmaker interface
  networking.firewall.trustedInterfaces = ["netmaker"];
}
