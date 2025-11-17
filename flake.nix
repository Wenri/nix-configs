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

    # Server deployment tools
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
        username = "nixos";
        type = "wsl";
      };

      # Desktop hosts
      nixos-gnome = {
        system = "x86_64-linux";
        username = "xsnow";
        type = "desktop";
      };
      nixos-plasma6 = {
        system = "x86_64-linux";
        username = "xsnow";
        type = "desktop";
      };
      irif = {
        system = "x86_64-linux";
        username = "xsnow";
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
  in {
    # Custom packages and modifications, exported as overlays
    overlays = import ./common/overlays {inherit inputs;};

    # Reusable nixos modules
    nixosModules = import ./common/modules/nixos;

    # Reusable home-manager modules
    homeManagerModules = import ./common/modules/home-manager;

    # NixOS system configurations - generated from hosts
    nixosConfigurations = lib.mapAttrs (hostname: cfg:
      mkNixosSystem {
        inherit hostname;
        inherit (cfg) system username type;
      })
    hosts;

    # Home-manager configurations - generated from hosts (standalone, for backward compatibility)
    homeConfigurations = lib.mapAttrs' (hostname: cfg:
      lib.nameValuePair "${cfg.username}@${hostname}" (mkHomeConfiguration {
        inherit hostname;
        inherit (cfg) username system;
      }))
    hosts;

    # Expose system configurations and custom packages
    packages = forAllSystems (system: let
      hostsForSystem = lib.filterAttrs (hostname: cfg: cfg.system == system) hosts;
      customPkgs = import ./common/pkgs (mkPkgs system);
    in
      (lib.mapAttrs (hostname: cfg:
        self.nixosConfigurations.${hostname}.config.system.build.toplevel)
      hostsForSystem) // customPkgs);

    # Formatter for 'nix fmt'
    formatter = forAllSystems (system: (mkPkgs system).alejandra);
  };
}
