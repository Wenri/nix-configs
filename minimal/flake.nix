{
  description = "NixOS-WSL configuration with home-manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
    defaultUsername = "nixos";

    # Supported systems for flake outputs
    systems = ["x86_64-linux"];
    forAllSystems = nixpkgs.lib.genAttrs systems;

    # Single source of truth for all hosts
    hosts = {
      wslnix = {
        system = "x86_64-linux";
      };
    };

    # Create properly configured pkgs instances for each system
    mkPkgs = system:
      import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

    mkNixosSystem = {
      hostname,
      system,
      username ? defaultUsername,
    }:
      lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs outputs hostname username;
        };
        modules = [
          inputs.nixos-wsl.nixosModules.default
          inputs.home-manager.nixosModules.home-manager
          ./nixos/common.nix
          # Home-manager integration
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {
              inherit inputs outputs hostname username;
            };
            home-manager.users.${username} = import ./home-manager/home.nix;
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
    # NixOS system configurations - generated from hosts
    nixosConfigurations = lib.mapAttrs (hostname: cfg:
      mkNixosSystem {
        inherit hostname;
        system = cfg.system;
      })
    hosts;

    # Home-manager configurations - generated from hosts
    homeConfigurations = lib.mapAttrs' (hostname: cfg:
      lib.nameValuePair "${defaultUsername}@${hostname}" (mkHomeConfiguration {
        inherit hostname;
        system = cfg.system;
      }))
    hosts;

    # Expose system configurations as packages - only for matching system
    packages = forAllSystems (system: let
      hostsForSystem = lib.filterAttrs (hostname: cfg: cfg.system == system) hosts;
    in
      lib.mapAttrs (hostname: cfg:
        self.nixosConfigurations.${hostname}.config.system.build.toplevel)
      hostsForSystem);

    # Formatter for 'nix fmt'
    formatter = forAllSystems (system: (mkPkgs system).alejandra);
  };
}
