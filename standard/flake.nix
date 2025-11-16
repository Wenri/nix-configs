{
  description = "NixOS configuration with custom modules and home-manager";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    nur = {
      url = "github:nix-community/NUR";
    };

    nix-vscode-extensions = {
      url = "github:nix-community/nix-vscode-extensions";
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
    defaultUsername = "xsnow";

    # Supported systems for flake outputs
    systems = [
      "aarch64-linux"
      "i686-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;

    # Single source of truth for all hosts
    hosts = {
      nixos-gnome = {
        system = "x86_64-linux";
      };
      nixos-plasma6 = {
        system = "x86_64-linux";
      };
      irif = {
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
          inputs.home-manager.nixosModules.home-manager
          ./nixos/configuration-${hostname}.nix
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
    # Custom packages - accessible through 'nix build', 'nix shell', etc
    packages = forAllSystems (system: import ../common/pkgs (mkPkgs system));

    # Formatter for 'nix fmt'
    formatter = forAllSystems (system: (mkPkgs system).alejandra);

    # Custom packages and modifications, exported as overlays
    overlays = import ../common/overlays {inherit inputs;};

    # Reusable nixos modules
    nixosModules = import ../common/modules/nixos;

    # Reusable home-manager modules
    homeManagerModules = import ../common/modules/home-manager;

    # NixOS system configurations - generated from hosts
    nixosConfigurations = lib.mapAttrs (hostname: cfg:
      mkNixosSystem {
        inherit hostname;
        system = cfg.system;
      })
    hosts;

    # Home-manager configurations - generated from hosts (standalone, for backward compatibility)
    homeConfigurations = lib.mapAttrs' (hostname: cfg:
      lib.nameValuePair "${defaultUsername}@${hostname}" (mkHomeConfiguration {
        inherit hostname;
        system = cfg.system;
      }))
    hosts;
  };
}
