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

    # Default username for all configurations
    defaultUsername = "wenri";

    # Create properly configured pkgs instances for each system
    mkPkgs = system:
      import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

    mkNixosSystem = {
      hostname,
      system,
      facterFile,
      username ? defaultUsername,
    }:
      lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs outputs hostname username;
        };
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
      username ? defaultUsername,
      hostname,
      system,
    }:
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = mkPkgs system;
        extraSpecialArgs = {
          inherit inputs outputs hostname username;
        };
        modules = [./home-manager/home.nix];
      };
  in {
    # NixOS system configurations
    nixosConfigurations = {
      freenix = mkNixosSystem {
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

    # Home-manager configurations
    homeConfigurations = {
      "${defaultUsername}@matrix" = mkHomeConfiguration {
        hostname = "matrix";
        system = "x86_64-linux";
      };

      "${defaultUsername}@freenix" = mkHomeConfiguration {
        hostname = "freenix";
        system = "aarch64-linux";
      };
    };

    # Expose system configurations as packages
    packages = {
      x86_64-linux.matrix = self.nixosConfigurations.matrix.config.system.build.toplevel;
      aarch64-linux.freenix = self.nixosConfigurations.freenix.config.system.build.toplevel;
    };

    # Formatter for 'nix fmt'
    formatter = lib.genAttrs ["x86_64-linux" "aarch64-linux"] (system: (mkPkgs system).alejandra);
  };
}
