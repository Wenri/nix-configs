# Overlay to make store paths accessible both inside and outside proot
# Replaces /nix/store symlinks with /data/data/com.termux.nix/files/usr/nix/store
{inputs, ...}: final: prev: let
  # The absolute prefix for nix store outside proot
  absolutePrefix = "/data/data/com.termux.nix/files/usr";
  
  # Helper to rewrite symlinks in a derivation's output
  makeAbsoluteSymlinks = drv:
    final.runCommand "${drv.name or drv.pname}-absolute-symlinks" 
      {
        inherit drv;
        nativeBuildInputs = [final.rsync];
        # Preserve passthru attributes like interpreter, meta, etc.
        passthru = drv.passthru or {};
        # Preserve all standard derivation outputs
        outputs = drv.outputs or ["out"];
      } ''
      # Copy the entire derivation output
      rsync -a "$drv/" "$out/"
      
      # Find all symlinks and rewrite them if they point to /nix/store
      find "$out" -type l | while read -r link; do
        target=$(readlink "$link")
        # If symlink points to /nix/store, rewrite with absolute prefix
        if [[ "$target" == /nix/store/* ]]; then
          rm "$link"
          ln -s "${absolutePrefix}$target" "$link"
        fi
      done
    '';
in {
  # Override lib to add helper function
  lib = prev.lib // {
    makeAbsoluteSymlinks = makeAbsoluteSymlinks;
  };
  
  # Note: Disabled buildEnv override as it breaks python.withPackages and similar
  # Use makeAbsoluteSymlinks manually on specific packages if needed
  # buildEnv = args:
  #   makeAbsoluteSymlinks (prev.buildEnv args);
}
