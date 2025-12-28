# Shizuku rish shell integration for nix-on-droid
# Extracts dex file from Shizuku APK and provides rish command
# Reference: https://shizuku.rikka.app/guide/setup/
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.shizuku;

  # Fetch Shizuku APK from GitHub releases
  shizukuApk = pkgs.fetchurl {
    url = "https://github.com/RikkaApps/Shizuku/releases/download/v13.6.0/shizuku-v13.6.0.r1086.2650830c-release.apk";
    hash = "sha256-bic6sOmRxOebyLG7ubndc5zKwahxKlQaIUB4iGt7eQ8=";
  };

  # Extract the dex file from the APK
  shizukuDex = pkgs.runCommand "rish_shizuku.dex" {
    nativeBuildInputs = [pkgs.unzip];
  } ''
    unzip -p ${shizukuApk} assets/rish_shizuku.dex > $out
  '';

  # Create the rish shell script (based on official template from Shizuku)
  # Note: Android 14+ requires dex to be read-only, which Nix store already guarantees
  rishScript = pkgs.writeScriptBin "rish" ''
    #!/system/bin/sh
    DEX="${shizukuDex}"

    if [ ! -f "$DEX" ]; then
      echo "Cannot find $DEX, please check the tutorial in Shizuku app"
      exit 1
    fi

    # Application ID for Termux/nix-on-droid
    [ -z "$RISH_APPLICATION_ID" ] && export RISH_APPLICATION_ID="com.termux.nix"
    exec /system/bin/app_process -Djava.class.path="$DEX" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "$@"
  '';
in {
  options.programs.shizuku = {
    enable = lib.mkEnableOption "Shizuku rish shell integration";

    package = lib.mkOption {
      type = lib.types.package;
      default = rishScript;
      description = "The rish package to use";
    };

    applicationId = lib.mkOption {
      type = lib.types.str;
      default = "com.termux.nix";
      description = "The application ID of the terminal app";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.packages = [cfg.package];
  };
}
