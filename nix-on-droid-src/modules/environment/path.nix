# Copyright (c) 2019-2022, see AUTHORS. Licensed under MIT License, see LICENSE.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.environment;
  
  storePrefix = if config.build.absoluteStorePrefix != null
    then config.build.absoluteStorePrefix
    else "";
in

{

  ###### interface

  options = {

    environment = {
      packages = mkOption {
        type = types.listOf types.package;
        default = [ ];
        description = "List of packages to be installed as user packages.";
      };

      path = mkOption {
        type = types.package;
        readOnly = true;
        internal = true;
        description = "Derivation for installing user packages.";
      };

      extraOutputsToInstall = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "doc" "info" "devdoc" ];
        description = "List of additional package outputs to be installed as user packages.";
      };
    };

  };


  ###### implementation

  config = {

    build.activation.installPackages = let
      prefix = if config.build.absoluteStorePrefix != null
        then config.build.absoluteStorePrefix
        else "";
    in ''
      if [[ -e "${config.user.home}/.nix-profile/manifest.json" ]]; then
        # manual removal and installation as two non-atomical steps is required
        # because of https://github.com/NixOS/nix/issues/6349

        nix_previous="$(command -v nix)"

        nix profile list \
          | grep 'nix-on-droid-path$' \
          | cut -d ' ' -f 4 \
          | xargs -t $DRY_RUN_CMD nix profile remove $VERBOSE_ARG

        $DRY_RUN_CMD $nix_previous profile install ${cfg.path}

        unset nix_previous
      else
        $DRY_RUN_CMD nix-env --install ${cfg.path}
      fi
      
      ${optionalString (prefix != "") ''
        # Rewrite symlinks inside the user-environment to use absolute paths
        # The user-environment is read-only, so we create a mutable copy
        userenv=$(readlink -f "${config.user.home}/.nix-profile")
        if [[ -d "$userenv" && "$userenv" == /nix/store/* ]]; then
          noteEcho "Rewriting user-environment symlinks for outside-proot access"
          tmpdir=$(mktemp -d)
          
          # Copy structure and rewrite symlinks
          for item in "$userenv"/*; do
            name=$(basename "$item")
            if [[ -L "$item" ]]; then
              target=$(readlink "$item")
              if [[ "$target" == /nix/store/* ]]; then
                ln -s "${prefix}$target" "$tmpdir/$name"
              else
                ln -s "$target" "$tmpdir/$name"
              fi
            elif [[ -d "$item" ]]; then
              ln -s "${prefix}$item" "$tmpdir/$name"
            fi
          done
          
          # Create a new generation pointing to our modified environment
          gen_num=$(ls /nix/var/nix/profiles/per-user/nix-on-droid/ | grep -E '^profile-[0-9]+-link$' | sed 's/profile-//' | sed 's/-link//' | sort -n | tail -1)
          new_gen=$((gen_num + 1))
          
          # Move the temp dir to a fixed location and update profile
          fixed_env="${config.user.home}/.local/share/nix-on-droid/user-environment"
          mkdir -p "$(dirname "$fixed_env")"
          rm -rf "$fixed_env"
          mv "$tmpdir" "$fixed_env"
          
          # Update the profile to point to our fixed environment
          rm -f "/nix/var/nix/profiles/per-user/nix-on-droid/profile"
          ln -s "$fixed_env" "/nix/var/nix/profiles/per-user/nix-on-droid/profile"
        fi
      ''}
    '';

    environment = {
      packages = [
        (pkgs.callPackage ../../nix-on-droid { nix = config.nix.package; })
        pkgs.bashInteractive
        pkgs.cacert
        pkgs.coreutils
        pkgs.less # since nix tools really want a pager available, #27
        config.nix.package
      ];

      path = pkgs.buildEnv {
        name = "nix-on-droid-path";

        paths = cfg.packages;

        inherit (cfg) extraOutputsToInstall;

        meta = {
          description = "Environment of packages installed through Nix-on-Droid.";
        };
        
        # Rewrite symlinks to use absolute store prefix
        postBuild = optionalString (storePrefix != "") ''
          # Find and rewrite all symlinks pointing to /nix/store
          find $out -type l | while read -r link; do
            target=$(readlink "$link")
            if [[ "$target" == /nix/store/* ]]; then
              rm "$link"
              ln -s "${storePrefix}$target" "$link"
            fi
          done
        '';
      };
    };

  };

}
