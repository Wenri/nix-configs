# rish - Shizuku shell for privileged Android commands
# Reference: https://shizuku.rikka.app/guide/setup/
{ lib, runCommand, fetchurl, unzip, writeTextFile, installationDir ? null }:

let
  version = "13.6.0";

  # Prefix for Android paths (empty string if not on Android)
  prefix = if installationDir != null then installationDir else "";

  # Fetch Shizuku APK from GitHub releases
  shizukuApk = fetchurl {
    url = "https://github.com/RikkaApps/Shizuku/releases/download/v${version}/shizuku-v${version}.r1086.2650830c-release.apk";
    hash = "sha256-bic6sOmRxOebyLG7ubndc5zKwahxKlQaIUB4iGt7eQ8=";
  };

  # Extract the dex file from the APK
  shizukuDex = runCommand "rish_shizuku.dex" {
    nativeBuildInputs = [ unzip ];
  } ''
    unzip -p ${shizukuApk} assets/rish_shizuku.dex > $out
  '';

in writeTextFile {
  name = "rish-${version}";
  executable = true;
  destination = "/bin/rish";

  # Script based on official Shizuku template
  # Note: Android 14+ requires dex to be read-only, which Nix store guarantees
  text = ''
    #!/system/bin/sh
    DEX="${prefix}${shizukuDex}"

    if [ ! -f "$DEX" ]; then
      echo "Cannot find $DEX, please check the tutorial in Shizuku app"
      exit 1
    fi

    # Application ID for Termux/nix-on-droid
    [ -z "$RISH_APPLICATION_ID" ] && export RISH_APPLICATION_ID="com.termux.nix"
    exec /system/bin/app_process -Djava.class.path="$DEX" /system/bin --nice-name=rish rikka.shizuku.shell.ShizukuShellLoader "$@"
  '';

  meta = {
    description = "Shizuku shell for privileged Android commands";
    homepage = "https://shizuku.rikka.app/";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "rish";
  };
}
