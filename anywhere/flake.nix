{
  description = "NixOS configuration with nixos-anywhere and home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    ...
  } @ inputs: let
    inherit (self) outputs;
    lib = nixpkgs.lib;

    mkNixosSystem = {
      hostname,
      system,
      facterFile,
    }:
      lib.nixosSystem {
        inherit system;
        specialArgs = {inherit inputs outputs;};
        modules = [
          inputs.disko.nixosModules.disko
          inputs.nixos-facter-modules.nixosModules.facter
          ./nixos/host-${hostname}.nix
          {
            config.facter.reportPath =
              if builtins.pathExists facterFile
              then facterFile
              else throw "Missing facter report: ${facterFile}. Run nixos-anywhere with --generate-hardware-config nixos-facter ${facterFile}";
          }
        ];
      };

    mkHomeConfiguration = {
      username,
      hostname,
      system,
    }:
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.${system};
        extraSpecialArgs = {inherit inputs outputs;};
        modules = [./home-manager/home.nix];
      };
  in {
    nixosConfigurations = {
      freevm-nixos-facter = mkNixosSystem {
        hostname = "freenix";
        system = "aarch64-linux";
        facterFile = ./nixos/facter-free.json;
      };

      matrix = mkNixosSystem {
        hostname = "matrix";
        system = "x86_64-linux";
        facterFile = ./nixos/facter-matrix.json;
      };
    };

    homeConfigurations = {
      "wenri@matrix" = mkHomeConfiguration {
        username = "wenri";
        hostname = "matrix";
        system = "x86_64-linux";
      };

      "wenri@freenix" = mkHomeConfiguration {
        username = "wenri";
        hostname = "freenix";
        system = "aarch64-linux";
      };
    };
  };
}
