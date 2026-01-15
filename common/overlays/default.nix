# Overlay entry point - imports and exports all overlays
#
# Parameters:
#   inputs          - Flake inputs (required)
#   lib             - nixpkgs lib (default: inputs.nixpkgs.lib)
#   installationDir - Android installation directory for path translation (optional)
#
# Exports:
#   additions        - Custom packages from common/pkgs/
#   modifications    - Package modifications
#   unstable-packages - Access nixpkgs-unstable via pkgs.unstable.*
#   master-packages   - Access nixpkgs-master via pkgs.master.*
{ inputs, lib ? inputs.nixpkgs.lib, installationDir ? null, ... }:
let
  channels = import ./channels.nix { inherit inputs; };
in {
  additions = import ./additions.nix;
  modifications = import ./modifications.nix { inherit lib installationDir; };
  inherit (channels) unstable-packages master-packages;
}
