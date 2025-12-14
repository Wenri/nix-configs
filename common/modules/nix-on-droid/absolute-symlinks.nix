# Module to rewrite symlinks in nix-on-droid generation to use absolute paths
# This makes the nix store accessible both inside and outside proot
{
  config,
  lib,
  pkgs,
  ...
}: let
  absolutePrefix = "/data/data/com.termux.nix/files/usr";
in {
  options = {
    build.useAbsoluteSymlinks = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to rewrite symlinks in the profile to use absolute paths.
        This makes the nix store accessible both inside and outside proot.
      '';
    };
  };

  config = lib.mkIf config.build.useAbsoluteSymlinks {
    # Add an activation script to rewrite symlinks after profile is linked
    build.activationAfter.rewriteSymlinks = ''
      noteEcho "Rewriting symlinks to use absolute paths"
      
      # Rewrite symlinks in key locations
      for link in /nix/var/nix/profiles/nix-on-droid /nix/var/nix/profiles/nix-on-droid-*-link; do
        if [[ -L "$link" ]]; then
          target=$(readlink "$link")
          if [[ "$target" == /nix/store/* ]]; then
            $VERBOSE_ECHO "Rewriting profile link: $link"
            $DRY_RUN_CMD rm "$link"
            $DRY_RUN_CMD ln -s "${absolutePrefix}$target" "$link"
          fi
        fi
      done
      
      # Also rewrite the home profile symlink
      if [[ -L "$HOME/.nix-profile" ]]; then
        target=$(readlink "$HOME/.nix-profile")
        if [[ "$target" == /nix/* && "$target" != ${absolutePrefix}/* ]]; then
          $VERBOSE_ECHO "Rewriting home profile: $HOME/.nix-profile"
          $DRY_RUN_CMD rm "$HOME/.nix-profile"
          $DRY_RUN_CMD ln -s "${absolutePrefix}$target" "$HOME/.nix-profile"
        fi
      fi
    '';
  };
}
