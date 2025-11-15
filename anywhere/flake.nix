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

    # Supported systems for flake outputs
    systems = [
      "aarch64-linux"
      "x86_64-linux"
    ];
    forAllSystems = nixpkgs.lib.genAttrs systems;

    # Single source of truth for all hosts
    hosts = {
      freenix = {
        system = "aarch64-linux";
      };
      matrix = {
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
    }: let
      facterFile = ./nixos/facter-${hostname}.json;
    in
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
