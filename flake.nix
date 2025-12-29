{
  description = "Unified NixOS configurations with shared infrastructure";

  inputs = {
    self.submodules = true;
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-master.url = "github:NixOS/nixpkgs/master";

    nur.url = "github:nix-community/NUR";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-on-droid = {
      url = "path:./submodules/nix-on-droid";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

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

    systems = ["aarch64-linux" "x86_64-linux"];
    forAllSystems = lib.genAttrs systems;

    mkPkgs = system:
      import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

    # Single source of truth for ALL hosts
    hosts = {
      # NixOS hosts
      wslnix        = { system = "x86_64-linux";  username = "wenri"; type = "wsl"; };
      nixos-gnome   = { system = "x86_64-linux";  username = "wenri"; type = "desktop"; };
      nixos-plasma6 = { system = "x86_64-linux";  username = "wenri"; type = "desktop"; };
      irif          = { system = "x86_64-linux";  username = "wenri"; type = "desktop"; };
      matrix        = { system = "x86_64-linux";  username = "wenri"; type = "server"; };
      freenix       = { system = "aarch64-linux"; username = "wenri"; type = "server"; };
      # Android host
      nix-on-droid  = { system = "aarch64-linux"; username = "wenri"; type = "android"; };
    };

    # Filter by type
    nixosHosts = lib.filterAttrs (_: cfg: cfg.type != "android") hosts;
    androidHosts = lib.filterAttrs (_: cfg: cfg.type == "android") hosts;

    # Android utilities (built once, reused)
    android = import ./common/lib/android.nix {
      pkgs = import nixpkgs {
        system = "aarch64-linux";
        config.allowUnfree = true;
        overlays = [
          nix-on-droid.overlays.default
          outputs.overlays.additions
          outputs.overlays.modifications
          outputs.overlays.unstable-packages
          outputs.overlays.master-packages
        ];
      };
      glibcSrc = ./submodules/glibc;
      fakechrootSrc = ./submodules/fakechroot;
    };

    # NixOS system builder
    mkNixosSystem = { hostname, system, username, type }:
      lib.nixosSystem {
        inherit system;
        specialArgs = { inherit inputs outputs hostname username; };
        modules = [
          inputs.home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs outputs hostname username; };
              users.${username} = import ./hosts/${hostname}/home.nix;
            };
          }
        ] ++ (
          if type == "wsl" then [
            inputs.nixos-wsl.nixosModules.default
            ./hosts/${hostname}/configuration.nix
          ] else if type == "server" then [
            inputs.disko.nixosModules.disko
            inputs.nixos-facter-modules.nixosModules.facter
            ./hosts/${hostname}/configuration.nix
            { config.facter.reportPath = ./hosts/${hostname}/facter.json; }
          ] else [
            ./hosts/${hostname}/configuration.nix
          ]
        );
      };

    # Android system builder
    mkAndroidSystem = { hostname, username, ... }:
      nix-on-droid.lib.nixOnDroidConfiguration {
        pkgs = android.pkgs;
        home-manager-path = home-manager.outPath;
        extraSpecialArgs = {
          inherit inputs outputs hostname username;
          inherit (android) androidGlibc patchPackageForAndroidGlibc;
        };
        modules = [
          ./hosts/${hostname}/configuration.nix
          android.nixOnDroidModule
        ];
      };

    # Home-manager standalone builder
    mkHomeConfiguration = { username, hostname, system, ... }:
      inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = mkPkgs system;
        extraSpecialArgs = { inherit inputs outputs hostname username; };
        modules = [./hosts/${hostname}/home.nix];
      };

  in {
    overlays = import ./common/overlays { inherit inputs; };
    nixosModules = import ./common/modules/nixos;
    homeModules = import ./common/modules/home-manager;
    androidModules = import ./common/modules/android;

    # NixOS configurations (all non-android hosts)
    nixosConfigurations = lib.mapAttrs (hostname: cfg:
      mkNixosSystem { inherit hostname; inherit (cfg) system username type; }
    ) nixosHosts;

    # Android configurations (all android hosts)
    nixOnDroidConfigurations = lib.mapAttrs (hostname: cfg:
      mkAndroidSystem { inherit hostname; inherit (cfg) system username; }
    ) androidHosts // {
      # nix-on-droid expects "default"
      default = mkAndroidSystem { hostname = "nix-on-droid"; username = "wenri"; };
    };

    # Standalone home-manager (for NixOS hosts, backward compat)
    homeConfigurations = lib.mapAttrs' (hostname: cfg:
      lib.nameValuePair "${cfg.username}@${hostname}" (mkHomeConfiguration {
        inherit hostname;
        inherit (cfg) username system;
      })
    ) nixosHosts;

    # Packages output
    packages = forAllSystems (system: let
      hostsForSystem = lib.filterAttrs (_: cfg: cfg.system == system) nixosHosts;
      customPkgs = import ./common/pkgs { pkgs = mkPkgs system; inherit android; };
    in
      (lib.mapAttrs (hostname: _:
        self.nixosConfigurations.${hostname}.config.system.build.toplevel
      ) hostsForSystem)
      // customPkgs
    );

    formatter = forAllSystems (system: (mkPkgs system).alejandra);
  };
}
