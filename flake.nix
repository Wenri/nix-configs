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

    # Nix-on-Droid for Android - using submodule
    nix-on-droid = {
      url = "path:./submodules/nix-on-droid";
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
      # Installation directory for nix-on-droid (outside proot)
      installationDir = "/data/data/com.termux.nix/files/usr";

      # Build Android-patched glibc using the Termux patches from overlays
      # Uses glibc 2.40 from submodules/glibc with Termux's Android-specific patches
      # Configured with Android prefix so paths are baked in correctly
      androidGlibc = let
        glibcOverlay = import ./common/overlays/glibc.nix {
          glibcSrc = ./submodules/glibc;
        } basePkgs basePkgs;
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
      standardGccLib = basePkgs.stdenv.cc.cc.lib;

      # Patched gcc-lib with symlinks rewritten for Android
      # gcc-lib contains symlinks to gcc-libgcc that point to /nix/store/...
      # We need to rewrite these to /data/data/.../nix/store/...
      androidGccLib = basePkgs.runCommand "gcc-lib-android" {} ''
        cp -r ${standardGccLib} $out
        chmod -R u+w $out

        # Rewrite symlinks that point to /nix/store to use the Android prefix
        find $out -type l | while read -r link; do
          target=$(readlink "$link")
          if echo "$target" | grep -q "^/nix/store"; then
            new_target="${installationDir}$target"
            rm "$link"
            ln -s "$new_target" "$link"
          fi
        done || true
      '';

      # Function to patch a package for Android/nix-on-droid:
      # 1. Replace standard glibc with Android glibc in interpreter and RPATH
      # 2. Prefix ALL /nix/store paths with Android installation directory
      #    (needed because ld.so filters RUNPATH entries that don't exist,
      #    and /nix/store doesn't exist on Android)
      # 3. Preserve symlink structure (important for packages like cursor-cli)
      patchPackageForAndroidGlibc = pkg: basePkgs.runCommand "${pkg.pname or pkg.name or "package"}-android" ({
        nativeBuildInputs = [ basePkgs.patchelf basePkgs.file ];
        passthru = pkg.passthru or {};
      } // (if pkg ? meta.priority then {meta.priority = pkg.meta.priority;} else {})) ''
        # Copy the entire package, preserving symlinks (no -L flag!)
        # This is important for packages like cursor-cli where bin/cmd -> ../share/app/cmd
        cp -r ${pkg} $out
        chmod -R u+w $out
        
        # Rewrite symlinks that point to /nix/store to use the Android prefix
        find $out -type l | while read -r link; do
          target=$(readlink "$link")
          if echo "$target" | grep -q "^/nix/store"; then
            new_target="${installationDir}$target"
            rm "$link"
            ln -s "$new_target" "$link"
          fi
        done || true
        
        # Find and patch script files (hashbangs and /nix/store paths in content)
        # IMPORTANT: First replace self-references (to original package) with $out,
        # then prefix remaining /nix/store paths with Android installation directory
        ORIG_STORE_PATH="${pkg}"  # Original package store path

        find $out -type f | while read -r file; do
          # Check if it's a text file with a hashbang
          if head -c 2 "$file" 2>/dev/null | grep -q "^#!"; then
            # It's a script - patch paths in the content
            if grep -q "/nix/store" "$file" 2>/dev/null; then
              # Step 1: Replace self-references (original package path) with $out
              # This ensures wrapper scripts call their own patched binaries
              sed -i "s|$ORIG_STORE_PATH|$out|g" "$file"
              # Step 2: Prefix remaining /nix/store paths with Android prefix
              # BUT skip if already prefixed (locally-built packages already have Android paths)
              if ! grep -qF "${installationDir}/nix/store" "$file" 2>/dev/null; then
                sed -i "s|/nix/store|${installationDir}/nix/store|g" "$file"
              fi
            fi
          fi
        done || true

        # Find and patch all ELF files
        find $out -type f | while read -r file; do
          # Skip if not ELF
          if ! file "$file" 2>/dev/null | grep -q "ELF.*dynamic"; then
            continue
          fi

          # Patch interpreter to use Android-prefixed path
          INTERP=$(patchelf --print-interpreter "$file" 2>/dev/null || echo "")
          if [ -n "$INTERP" ] && echo "$INTERP" | grep -q "^/nix/store"; then
            # Use Android glibc's ld.so with full Android prefix
            NEW_INTERP="${installationDir}${androidGlibc}/lib/ld-linux-aarch64.so.1"
            patchelf --set-interpreter "$NEW_INTERP" "$file" 2>/dev/null || true
          fi

          # Patch RPATH: prefix all /nix/store paths with Android installation directory
          # Also redirect standard glibc to Android glibc, and gcc-lib to patched version
          RPATH=$(patchelf --print-rpath "$file" 2>/dev/null || echo "")
          if [ -n "$RPATH" ] && echo "$RPATH" | grep -q "/nix/store"; then
            # First, redirect standard glibc to Android glibc
            NEW_RPATH=$(echo "$RPATH" | sed "s|${standardGlibc}|${androidGlibc}|g")
            # Replace standard gcc-lib with patched version (has rewritten symlinks)
            NEW_RPATH=$(echo "$NEW_RPATH" | sed "s|${standardGccLib}|${androidGccLib}|g")
            # Then, prefix all /nix/store paths with Android installation directory
            NEW_RPATH=$(echo "$NEW_RPATH" | sed "s|/nix/store|${installationDir}/nix/store|g")
            patchelf --set-rpath "$NEW_RPATH" "$file" 2>/dev/null || true
          fi
        done || true
      '';

      # Build Android-patched fakechroot using the separate module
      # All paths are hardcoded at compile time - no env vars needed
      androidFakechroot = import ./common/overlays/fakechroot.nix {
        inherit (basePkgs) stdenv patchelf fakechroot;
        inherit androidGlibc installationDir;
        src = ./submodules/fakechroot;
      };

      # Note: pack-audit.so no longer needed
      # Path translation (/nix/store -> Android prefix) is now built into ld.so
      # See elf/dl-android-paths.h in the glibc submodule

    in
      nix-on-droid.lib.nixOnDroidConfiguration {
        modules = [
          ./hosts/${hostname}/configuration.nix
          {
            # Add Android glibc and patched packages
            # gcc-lib is needed for libgcc_s.so.1 (nodejs, C++ apps use it via RPATH)
            environment.packages = [ androidGlibc androidFakechroot androidGccLib ];

            # Configure fakechroot login
            build.androidGlibc = androidGlibc;
            build.standardGlibc = standardGlibc;
            build.androidFakechroot = androidFakechroot;
            build.bashInteractive = patchPackageForAndroidGlibc basePkgs.bashInteractive;

            # Patch all environment.packages for Android glibc
            # This patches interpreter and RPATH to use the Android glibc prefix
            build.patchPackageForAndroidGlibc = patchPackageForAndroidGlibc;

            # Create ld.so.preload for automatic libfakechroot loading
            environment.etc."ld.so.preload".text = ''
              ${installationDir}${androidFakechroot}/lib/fakechroot/libfakechroot.so
            '';
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
        installationDir = "/data/data/com.termux.nix/files/usr";
        glibcOverlay = import ./common/overlays/glibc.nix {
          glibcSrc = ./submodules/glibc;
        } basePkgs basePkgs;
        androidGlibc = glibcOverlay.glibc;
      in {
        inherit androidGlibc;
        
        # Fakechroot with compile-time hardcoded paths (uses separate module)
        androidFakechroot = import ./common/overlays/fakechroot.nix {
          inherit (basePkgs) stdenv patchelf fakechroot;
          inherit androidGlibc installationDir;
          src = ./submodules/fakechroot;
        };
      } else {};
    in
      (lib.mapAttrs (hostname: _:
        self.nixosConfigurations.${hostname}.config.system.build.toplevel)
      hostsForSystem) // customPkgs // androidPackages);

    # Export Android glibc utilities for external use
    lib = {
      aarch64-linux = let
        basePkgs = mkPkgs "aarch64-linux";
        installationDir = "/data/data/com.termux.nix/files/usr";
        glibcOverlay = import ./common/overlays/glibc.nix {
          glibcSrc = ./submodules/glibc;
        } basePkgs basePkgs;
        androidGlibc = glibcOverlay.glibc;
        standardGlibc = basePkgs.glibc;
      in {
        inherit androidGlibc;
        
        # Android-patched fakechroot with compile-time hardcoded paths (uses separate module)
        androidFakechroot = import ./common/overlays/fakechroot.nix {
          inherit (basePkgs) stdenv patchelf fakechroot;
          inherit androidGlibc installationDir;
          src = ./submodules/fakechroot;
        };
        
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
