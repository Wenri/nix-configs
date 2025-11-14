{...}: {
  imports = [
    ./common.nix
    ./synapse.nix
  ];

  # Optimize Tailscale for this host's primary network interface
  services.tailscale.optimizedInterface = "ens3";
}
