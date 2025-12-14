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

    # Nix-on-Droid for Android - using local fork with absolute symlink support
    nix-on-droid = {
      url = "path:./nix-on-droid-src";
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
    }: let
      # Build Android-patched glibc using the Termux patches from overlays
      # Uses glibc 2.40 (from nixpkgs) with Termux's Android-specific patches
      androidGlibc = let
        glibcOverlay = import ./common/overlays/glibc.nix basePkgs basePkgs;
      in glibcOverlay.glibc;
      
      # Create base pkgs without glibc overlay (uses binary cache)
      basePkgs = import nixpkgs {
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
      
      standardGlibc = basePkgs.stdenv.cc.libc;
      
      # Function to patch a single package to use Android glibc
      # Uses patchelf to rewrite interpreter and RPATH at build time
      patchPackageForAndroidGlibc = pkg: basePkgs.runCommand "${pkg.pname or pkg.name or "package"}-android-glibc" ({
        nativeBuildInputs = [ basePkgs.patchelf basePkgs.file ];
        passthru = pkg.passthru or {};
      } // (if pkg ? meta.priority then {meta.priority = pkg.meta.priority;} else {})) ''
        echo "=== Patching package for Android glibc ==="
        echo "Package: ${pkg.pname or pkg.name or "unknown"}"
        echo "Standard glibc: ${standardGlibc}"
        echo "Android glibc: ${androidGlibc}"
        
        # Copy the entire package
        cp -rL ${pkg} $out
        chmod -R u+w $out
        
        # Find and patch all ELF files
        find $out -type f | while read -r file; do
          # Skip if not ELF
          if ! file "$file" 2>/dev/null | grep -q "ELF.*dynamic"; then
            continue
          fi
          
          PATCHED=0
          
          # Patch interpreter if it references standard glibc
          INTERP=$(patchelf --print-interpreter "$file" 2>/dev/null || echo "")
          if [ -n "$INTERP" ] && echo "$INTERP" | grep -q "${standardGlibc}"; then
            echo "Patching interpreter: $file"
            patchelf --set-interpreter "${androidGlibc}/lib/ld-linux-aarch64.so.1" "$file" 2>/dev/null || true
            PATCHED=1
          fi
          
          # Patch RPATH if it references standard glibc
          RPATH=$(patchelf --print-rpath "$file" 2>/dev/null || echo "")
          if [ -n "$RPATH" ] && echo "$RPATH" | grep -q "${standardGlibc}"; then
            NEW_RPATH=$(echo "$RPATH" | sed "s|${standardGlibc}/lib|${androidGlibc}/lib|g")
            echo "Patching RPATH: $file"
            echo "  Old: $RPATH"
            echo "  New: $NEW_RPATH"
            patchelf --set-rpath "$NEW_RPATH" "$file" 2>/dev/null || true
            PATCHED=1
          fi
          
          [ "$PATCHED" = "1" ] && echo "  ✓ Patched: $file"
        done
        
        echo "=== Patching complete ==="
      '';
    in
      nix-on-droid.lib.nixOnDroidConfiguration {
        modules = [
          ./hosts/${hostname}/configuration.nix
          {
            # Add Android glibc and patched packages
            # To use: environment.packages = map patchPackageForAndroidGlibc [ pkg1 pkg2 ... ];
            environment.packages = [ androidGlibc ];
          }
        ];

        extraSpecialArgs = {
          inherit inputs outputs hostname username androidGlibc patchPackageForAndroidGlibc;
        };

        pkgs = basePkgs;

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
      
      # Expose androidGlibc and androidFakechroot for aarch64-linux
      androidPackages = if system == "aarch64-linux" then let
        basePkgs = mkPkgs system;
        glibcOverlay = import ./common/overlays/glibc.nix basePkgs basePkgs;
        androidGlibc = glibcOverlay.glibc;
      in {
        inherit androidGlibc;
        
        # Fakechroot patched for Android glibc
        androidFakechroot = let
          fakechroot = basePkgs.fakechroot.overrideAttrs (oldAttrs: {
            version = "unstable-2024-12-14";
            src = basePkgs.fetchFromGitHub {
              owner = "Wenri";
              repo = "fakechroot";
              rev = "cfc132d2dbec1b5a87bd9a4b426e3ac62f06c14a";
              hash = "sha256-qgXqmKGD2vxhGgKPaIBDsyEhYNWy4vFUbwh36tOuQKk=";
            };
            patches = [];
          });
        in basePkgs.runCommand "fakechroot-android" {
          nativeBuildInputs = [ basePkgs.patchelf ];
        } ''
          echo "=== Building Android-patched fakechroot ==="
          cp -rL ${fakechroot} $out
          chmod -R u+w $out
          
          # Patch libfakechroot.so RUNPATH
          for lib in $out/lib/fakechroot/libfakechroot.so; do
            if [ -f "$lib" ]; then
              echo "  Patching RUNPATH: $lib"
              patchelf --set-rpath "${androidGlibc}/lib" "$lib" || true
            fi
          done
          
          # Patch executables
          for bin in $out/bin/fakechroot $out/bin/ldd.fakechroot; do
            if [ -f "$bin" ] && [ -x "$bin" ]; then
              if patchelf --print-interpreter "$bin" 2>/dev/null | grep -q ld-linux; then
                echo "  Patching: $bin"
                patchelf \
                  --set-interpreter "${androidGlibc}/lib/ld-linux-aarch64.so.1" \
                  --set-rpath "${androidGlibc}/lib" \
                  "$bin" 2>/dev/null || true
              fi
            fi
          done
          
          echo "=== Done ==="
        '';
      } else {};
    in
      (lib.mapAttrs (hostname: _:
        self.nixosConfigurations.${hostname}.config.system.build.toplevel)
      hostsForSystem) // customPkgs // androidPackages);

    # Export Android glibc utilities for external use
    lib = {
      aarch64-linux = let
        basePkgs = mkPkgs "aarch64-linux";
        glibcOverlay = import ./common/overlays/glibc.nix basePkgs basePkgs;
        androidGlibc = glibcOverlay.glibc;
        standardGlibc = basePkgs.glibc;
      in {
        inherit androidGlibc;
        
        # Android-patched fakechroot with elfloader audit/preload support
        androidFakechroot = let
          fakechroot = basePkgs.fakechroot.overrideAttrs (oldAttrs: {
            version = "unstable-2024-12-14";
            src = basePkgs.fetchFromGitHub {
              owner = "Wenri";
              repo = "fakechroot";
              rev = "cfc132d2dbec1b5a87bd9a4b426e3ac62f06c14a";
              hash = "sha256-qgXqmKGD2vxhGgKPaIBDsyEhYNWy4vFUbwh36tOuQKk=";
            };
            patches = [];
          });
        in basePkgs.runCommand "fakechroot-android" {
          nativeBuildInputs = [ basePkgs.patchelf ];
        } ''
          cp -rL ${fakechroot} $out
          chmod -R u+w $out
          for lib in $out/lib/fakechroot/libfakechroot.so; do
            [ -f "$lib" ] && patchelf --set-rpath "${androidGlibc}/lib" "$lib" || true
          done
          for bin in $out/bin/fakechroot $out/bin/ldd.fakechroot; do
            if [ -f "$bin" ] && patchelf --print-interpreter "$bin" 2>/dev/null | grep -q ld-linux; then
              patchelf --set-interpreter "${androidGlibc}/lib/ld-linux-aarch64.so.1" --set-rpath "${androidGlibc}/lib" "$bin" 2>/dev/null || true
            fi
          done
        '';
        
        # Function to patch a package to use Android glibc
        patchPackageForAndroidGlibc = pkg: basePkgs.runCommand "${pkg.pname or pkg.name or "package"}-android-glibc" ({
          nativeBuildInputs = [ basePkgs.patchelf basePkgs.file ];
          passthru = pkg.passthru or {};
        } // (if pkg ? meta.priority then {meta.priority = pkg.meta.priority;} else {})) ''
          echo "=== Patching package for Android glibc ==="
          echo "Package: ${pkg.pname or pkg.name or "unknown"}"
          
          cp -rL ${pkg} $out
          chmod -R u+w $out
          
          find $out -type f | while read -r file; do
            if ! file "$file" 2>/dev/null | grep -q "ELF.*dynamic"; then
              continue
            fi
            
            INTERP=$(patchelf --print-interpreter "$file" 2>/dev/null || echo "")
            if [ -n "$INTERP" ] && echo "$INTERP" | grep -q "${standardGlibc}"; then
              echo "Patching: $file"
              patchelf --set-interpreter "${androidGlibc}/lib/ld-linux-aarch64.so.1" "$file" 2>/dev/null || true
              RPATH=$(patchelf --print-rpath "$file" 2>/dev/null || echo "")
              if [ -n "$RPATH" ]; then
                NEW_RPATH=$(echo "$RPATH" | sed "s|${standardGlibc}/lib|${androidGlibc}/lib|g")
                patchelf --set-rpath "$NEW_RPATH" "$file" 2>/dev/null || true
              fi
            fi
          done
          echo "=== Done ==="
        '';
      };
    };

    # Formatter for 'nix fmt'
    formatter = forAllSystems (system: (mkPkgs system).alejandra);
  };
}
