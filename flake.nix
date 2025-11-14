{
  description = "NixOS + standalone home-manager config flakes to get you started!";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {nixpkgs, ...}: let
    forAllSystems = nixpkgs.lib.genAttrs [
      "aarch64-linux"
      "i686-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
  in {
    templates = {
      minimal = {
        description = ''
          Minimal flake - contains only the configs.
          Contains the bare minimum to migrate your existing legacy configs to flakes.
        '';
        path = ./minimal;
      };
      standard = {
        description = ''
          Standard flake - augmented with boilerplate for custom packages, overlays, and reusable modules.
          Perfect migration path for when you want to dive a little deeper.
        '';
        path = ./standard;
      };
      modular = {
        description = ''
          Modular configuration with nixos-anywhere and nixos-facter support.
          Features refactored architecture with separate modules for users, tailscale, synapse, etc.
          Best practices for production deployments with common base config and host-specific configs.
        '';
        path = ./anywhere;
      };
    };
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
  };
}
