# replace-android-dependencies.nix
# NixOS-style grafting for Android: recursive dependency patching
#
# This implements a similar approach to nixpkgs' replaceDependencies but for Android:
# 1. Use IFD (exportReferencesGraph) to discover full dependency closure
# 2. Recursively walk dependencies and create patched versions
# 3. Use hash mapping to update inter-package references
# 4. Apply prefix to pt_interp and RPATH for Android glibc (prefix is compile-time in patchnar)
# 5. Patch additional paths (like /nix/var/) in script string literals

{ lib, runCommand, writeText, nix, patchnar }:

{
  drv,
  androidGlibc,
  cutoffPackages ? [],
  # Additional paths to add prefix to in script strings
  # patchnar defaults include /nix/var/, so only add extras here
  addPrefixToPaths ? [],
}:

let
  inherit (builtins) attrNames attrValues hasAttr listToAttrs elem;
  inherit (lib) filter mapAttrs mapAttrsToList concatStringsSep;

  # Strip string context for use as map keys
  toContextlessString = x:
    builtins.unsafeDiscardStringContext (toString x);

  # Extract name portion from store path (without the 32-char hash prefix)
  # "/nix/store/abc123...-package-1.0" -> "package-1.0"
  # This ensures patched derivations have the same basename length as originals
  extractName = path:
    let
      base = baseNameOf path;
      # Store path format: <32-char-hash>-<name>
      # Skip 33 chars (32 hash + 1 hyphen) to get just the name
    in builtins.substring 33 (-1) base;

  # Get reference graph via IFD
  # This builds a derivation that exports the closure and parses it into a Nix attrset
  referencesOf = targetDrv:
    import (runCommand "references.nix" {
      exportReferencesGraph = ["graph" targetDrv];
    } ''
      (echo "{"
      while read path; do
        echo "  \"$path\" = ["
        read count
        read count  # skip size
        while [ "0" != "$count" ]; do
          read ref_path
          if [ "$ref_path" != "$path" ]; then
            echo "    \"$ref_path\""
          fi
          count=$(($count - 1))
        done
        echo "  ];"
      done < graph
      echo "}") > $out
    '').outPath;

  # Build complete reference graph for the input derivation
  rootReferences = referencesOf drv;

  # All packages in the closure
  allPackages = attrNames rootReferences;

  # Paths that should NOT be rewritten (cutoff packages)
  cutoffPaths = map toContextlessString cutoffPackages;

  # Determine if a package needs patching
  needsPatching = path:
    !(elem path cutoffPaths);

  # Packages that need to be patched
  packagesToPatch = filter needsPatching allPackages;

  # The rewrite memo is a fixed-point: each package's patched output
  # depends on the patched outputs of its dependencies
  #
  # lib.fix creates a recursive structure where 'self' refers to the final result.
  # Each package looks up its dependencies in 'self' (the memo).
  # Nix's lazy evaluation ensures dependencies are computed before dependents.
  rewriteMemo = lib.fix (self:
    listToAttrs (map (originalPath: {
      name = originalPath;
      value = let
        # Get this package's dependencies from the reference graph
        deps = rootReferences.${originalPath} or [];

        # Build hash mappings for dependencies that are being rewritten
        # Filter out mappings where old == new (cutoff packages map to themselves)
        depMappings = lib.filterAttrs (old: new: old != toString new) (
          listToAttrs (map (dep: {
            name = dep;
            value = self.${dep} or dep;  # Use rewritten dep or original
          }) deps)
        );

        # Write mappings to a file for patchnar
        # Format: OLD_PATH NEW_PATH (one per line)
        mappingsFile = writeText "mappings-${baseNameOf originalPath}" (
          concatStringsSep "\n" (mapAttrsToList (old: new:
            "${old} ${new}"
          ) depMappings)
        );

        # Build --add-prefix-to options
        addPrefixToArgs = concatStringsSep " " (map (p: "--add-prefix-to \"${p}\"") addPrefixToPaths);

      # IMPORTANT: Use same name portion (without hash) for hash mapping to work!
      # This ensures: /nix/store/OLD-name -> /nix/store/NEW-name (same length)
      # gcc-lib is handled by hash mapping (same package, different hash)
      # Only glibc needs explicit substitution (different package: standard -> android)
      in runCommand (extractName originalPath) {
        nativeBuildInputs = [ nix patchnar ];
        inherit originalPath;
      } ''
        nix-store --dump "$originalPath" | patchnar \
          --glibc "${androidGlibc}" \
          --mappings ${mappingsFile} \
          --self-mapping "$originalPath $out" \
          ${addPrefixToArgs} \
        | nix-store --restore $out
      '';
    }) packagesToPatch)

    # Cutoff packages map to themselves (no rewriting)
    // listToAttrs (map (pkg: {
      name = toContextlessString pkg;
      value = pkg;
    }) cutoffPackages)
  );

  # Get the patched version of the root derivation
  finalOutput = rewriteMemo.${toContextlessString drv};

  # Helper to look up patched version of a package from the memo
  # Returns the patched version if in memo, otherwise returns the original
  getPkg = pkg: rewriteMemo.${toContextlessString pkg} or pkg;

in {
  out = finalOutput;
  memo = rewriteMemo;
  inherit getPkg toContextlessString;
}
