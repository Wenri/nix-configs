# Shizuku rish shell integration for nix-on-droid
# Extracts dex file from Shizuku APK and provides rish command
# Reference: https://oddity.oddineers.co.uk/2024/01/14/termux-shizuku-and-rish-configuration-for-android-14/
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.shizuku;

  # Fetch Shizuku APK from GitHub releases
  shizukuApk = pkgs.fetchurl {
    url = "https://github.com/RikkaApps/Shizuku/releases/download/v13.5.4/shizuku-v13.5.4.r1049.0e53409-release.apk";
    hash = "sha256-oFgyzjcWr7H8zPRvNIAG0qKWynd+H/PSI3l9x00Gsx8=";
  };

  # Extract the dex file from the APK
  shizukuDex = pkgs.runCommand "rish_shizuku.dex" {
    nativeBuildInputs = [pkgs.unzip];
  } ''
    unzip -p ${shizukuApk} assets/rish_shizuku.dex > $out
  '';

  # Create the rish shell script
  # Based on the official rish script from Shizuku
  rishScript = pkgs.writeShellScriptBin "rish" ''
    #!/bin/sh
    # rish - Shizuku shell interface
    # Provides ADB-level shell access via Shizuku

    DEX="${shizukuDex}"

    if [ ! -f "$DEX" ]; then
      echo "Error: rish_shizuku.dex not found at $DEX" >&2
      exit 1
    fi

    # Check if Shizuku is running
    if ! /system/bin/app_process -Djava.class.path="$DEX" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader --version >/dev/null 2>&1; then
      echo "Error: Shizuku is not running or not accessible" >&2
      echo "Make sure Shizuku app is running with ADB or root privileges" >&2
      exit 1
    fi

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
  };

  config = lib.mkIf cfg.enable {
    environment.packages = [cfg.package];
  };
}
