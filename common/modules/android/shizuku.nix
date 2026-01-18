# Shizuku rish shell integration for nix-on-droid
# Reference: https://shizuku.rikka.app/guide/setup/
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.shizuku;
in {
  options.programs.shizuku = {
    enable = lib.mkEnableOption "Shizuku rish shell integration";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rish;
      description = "The rish package to use";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.packages = [cfg.package];
  };
}
