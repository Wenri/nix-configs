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

    # All NixOS hosts (non-Android)
    hosts = {
      wslnix      = { system = "x86_64-linux";  username = "wenri"; type = "wsl"; };
      nixos-gnome = { system = "x86_64-linux";  username = "wenri"; type = "desktop"; };
      nixos-plasma6 = { system = "x86_64-linux"; username = "wenri"; type = "desktop"; };
      irif        = { system = "x86_64-linux";  username = "wenri"; type = "desktop"; };
      matrix      = { system = "x86_64-linux";  username = "wenri"; type = "server"; };
      freenix     = { system = "aarch64-linux"; username = "wenri"; type = "server"; };
    };

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

    nixosConfigurations = lib.mapAttrs (hostname: cfg:
      mkNixosSystem { inherit hostname; inherit (cfg) system username type; }
    ) hosts;

    nixOnDroidConfigurations.default = nix-on-droid.lib.nixOnDroidConfiguration {
      pkgs = android.pkgs or (mkPkgs "aarch64-linux");
      home-manager-path = home-manager.outPath;
      extraSpecialArgs = {
        inherit inputs outputs;
        hostname = "nix-on-droid";
        username = "wenri";
        inherit (android) androidGlibc patchPackageForAndroidGlibc;
      };
      modules = [
        ./hosts/nix-on-droid/configuration.nix
        {
          environment.packages = with android; [ glibc fakechroot gccLib ];
          build.androidGlibc = android.glibc;
          build.androidFakechroot = android.fakechroot;
          build.bashInteractive = android.patchPackage android.pkgs.bashInteractive;
          build.patchPackageForAndroidGlibc = android.patchPackage;
          environment.etc."ld.so.preload".text = ''
            ${android.installationDir}${android.fakechroot}/lib/fakechroot/libfakechroot.so
          '';
        }
      ];
    };

    homeConfigurations = lib.mapAttrs' (hostname: cfg:
      lib.nameValuePair "${cfg.username}@${hostname}" (mkHomeConfiguration {
        inherit hostname;
        inherit (cfg) username system;
      })
    ) hosts;

    packages = forAllSystems (system: let
      hostsForSystem = lib.filterAttrs (_: cfg: cfg.system == system) hosts;
      customPkgs = import ./common/pkgs (mkPkgs system);
    in
      (lib.mapAttrs (hostname: _:
        self.nixosConfigurations.${hostname}.config.system.build.toplevel
      ) hostsForSystem)
      // customPkgs
      // (lib.optionalAttrs (system == "aarch64-linux") {
        androidGlibc = android.glibc;
        androidFakechroot = android.fakechroot;
      })
    );

    formatter = forAllSystems (system: (mkPkgs system).alejandra);
  };
}
