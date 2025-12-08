{
  description = "Unified NixOS configurations with shared infrastructure";

  inputs = {
    self.submodules = true;
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

    nur.url = "github:nix-community/NUR";

    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    # WSL-specific
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Home-manager (master for nix-on-droid, follows nixpkgs)
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Nix-on-Droid for Android
    nix-on-droid = {
      url = "github:nix-community/nix-on-droid";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Server deployment tools
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-facter-modules.url = "github:numtide/nixos-facter-modules";
  };

  outputs = {
    self,
    nixpkgs,
    nix-on-droid,
    home-manager,
    ...
  } @ inputs: let
    inherit (self) outputs;
    lib = nixpkgs.lib;

    # Supported systems for flake outputs
    systems = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;

    # Single source of truth for all hosts
    hosts = {
      # WSL host
      wslnix = {
        system = "x86_64-linux";
        username = "wenri";
        type = "wsl";
      };

      # Desktop hosts
      nixos-gnome = {
        system = "x86_64-linux";
        username = "wenri";
        type = "desktop";
      };
      nixos-plasma6 = {
        system = "x86_64-linux";
        username = "wenri";
        type = "desktop";
      };
      irif = {
        system = "x86_64-linux";
        username = "wenri";
        type = "desktop";
      };

      # Server hosts
      matrix = {
        system = "x86_64-linux";
        username = "wenri";
        type = "server";
      };
      freenix = {
        system = "aarch64-linux";
        username = "wenri";
        type = "server";
      };

      # Android host (nix-on-droid)
      nix-on-droid = {
        system = "aarch64-linux";
        username = "wenri";
        type = "android";
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
      username,
      type,
    }: let
      # Base modules for all systems
      baseModules = [
        inputs.home-manager.nixosModules.home-manager
        # Home-manager integration
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = {
            inherit inputs outputs hostname username;
          };
          home-manager.users.${username} = import ./hosts/${hostname}/home.nix;
        }
      ];

      # Type-specific modules
      typeModules =
        if type == "wsl"
        then [
          inputs.nixos-wsl.nixosModules.default
          ./hosts/${hostname}/configuration.nix
        ]
        else if type == "desktop"
        then [
          ./hosts/${hostname}/configuration.nix
        ]
        else if type == "server"
        then let
          facterFile = ./hosts/${hostname}/facter.json;
        in [
          inputs.disko.nixosModules.disko
          inputs.nixos-facter-modules.nixosModules.facter
          ./hosts/${hostname}/configuration.nix
          {
            config.facter.reportPath =
              if builtins.pathExists facterFile
              then facterFile
              else throw "Missing facter report: ${facterFile}. Run nixos-anywhere with --generate-hardware-config nixos-facter ${facterFile}";
          }
        ]
        else throw "Unknown host type: ${type}";
    in
      lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs outputs hostname username;
        };
        modules = baseModules ++ typeModules;
      };

    mkHomeConfiguration = {
      username,
      hostname,
      system,
      ...
    }:
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = mkPkgs system;
        extraSpecialArgs = {
          inherit inputs outputs hostname username;
        };
        modules = [./hosts/${hostname}/home.nix];
      };

    # Helper to create nix-on-droid configurations
    mkNixOnDroidConfiguration = {
      hostname,
      system,
      username,
      ...
    }:
      nix-on-droid.lib.nixOnDroidConfiguration {
        modules = [
          ./hosts/${hostname}/configuration.nix
        ];

        extraSpecialArgs = {
          inherit inputs outputs hostname username;
        };

        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfree = true;
          overlays = [
            nix-on-droid.overlays.default
            outputs.overlays.additions
            outputs.overlays.modifications
            outputs.overlays.unstable-packages
            outputs.overlays.master-packages
          ];
        };

        home-manager-path = home-manager.outPath;
      };

    # Filter hosts by type
    nixosHosts = lib.filterAttrs (_: cfg: cfg.type != "android") hosts;
    androidHosts = lib.filterAttrs (_: cfg: cfg.type == "android") hosts;
  in {
    # Custom packages and modifications, exported as overlays
    overlays = import ./common/overlays {inherit inputs;};

    # Reusable nixos modules
    nixosModules = import ./common/modules/nixos;

    # Reusable home-manager modules
    homeModules = import ./common/modules/home-manager;

    # Reusable nix-on-droid modules
    nixOnDroidModules = import ./common/modules/nix-on-droid;

    # NixOS system configurations - generated from hosts (excluding android type)
    nixosConfigurations = lib.mapAttrs (hostname: cfg:
      mkNixosSystem {
        inherit hostname;
        inherit (cfg) system username type;
      })
    nixosHosts;

    # Nix-on-Droid configurations - generated from androidHosts
    # Note: nix-on-droid uses "default" as the standard configuration name
    nixOnDroidConfigurations =
      lib.mapAttrs (hostname: cfg:
        mkNixOnDroidConfiguration {
          inherit hostname;
          inherit (cfg) system username;
        })
      androidHosts
      // {
        # Also expose as "default" for `nix-on-droid switch --flake .`
        default = mkNixOnDroidConfiguration {
          hostname = "nix-on-droid";
          system = "aarch64-linux";
          username = "wenri";
        };
      };

    # Home-manager configurations - generated from nixosHosts (standalone, for backward compatibility)
    # Note: android hosts use nix-on-droid's integrated home-manager
    homeConfigurations = lib.mapAttrs' (hostname: cfg:
      lib.nameValuePair "${cfg.username}@${hostname}" (mkHomeConfiguration {
        inherit hostname;
        inherit (cfg) username system;
      }))
    nixosHosts;

    # Expose system configurations and custom packages
    packages = forAllSystems (system: let
      hostsForSystem = lib.filterAttrs (_: cfg: cfg.system == system) nixosHosts;
      customPkgs = import ./common/pkgs (mkPkgs system);
    in
      (lib.mapAttrs (hostname: _:
        self.nixosConfigurations.${hostname}.config.system.build.toplevel)
      hostsForSystem) // customPkgs);

    # Formatter for 'nix fmt'
    formatter = forAllSystems (system: (mkPkgs system).alejandra);
  };
}
