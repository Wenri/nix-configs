{...}: {
  imports = [
    ./common.nix
  ];

  networking.hostName = "freenix";

  # Optimize Tailscale for this host's primary network interface
  services.tailscale.optimizedInterface = "enp0s3";
}
