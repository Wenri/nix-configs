{
  config,
  lib,
  pkgs,
  inputs,
  outputs,
  ...
}: let
  keys = import ../../common/keys.nix;
  packages = import ../../common/packages.nix {inherit pkgs;};

  # SSH server configuration (uses shared hostKeys from keys.nix)
  sshdConfig = {
    Port = 2222;
    HostKey = map (k: k.path) keys.hostKeys;
    # AuthorizedKeysFile defaults to ".ssh/authorized_keys"
    PasswordAuthentication = false;
    PubkeyAuthentication = true;
    PrintMotd = true;
  };

  # Convert attrset to sshd_config format
  formatSshdConfig = cfg:
    lib.concatStringsSep "\n" (lib.flatten (lib.mapAttrsToList (
        name: value:
          if lib.isList value
          then map (v: "${name} ${toString v}") value
          else "${name} ${
            if lib.isBool value
            then
              (
                if value
                then "yes"
                else "no"
              )
            else toString value
          }"
      )
      cfg));

  sshdConfigFile = pkgs.writeText "sshd_config" (formatSshdConfig sshdConfig);

  # Termux-boot script to start sshd (uses config file directly from Nix store)
  sshd-start = pkgs.writeShellScript "start-sshd" ''
    exec ${pkgs.openssh}/bin/sshd -f ${sshdConfigFile}
  '';

  # Generate host key creation commands from keys.hostKeys
  hostKeyGenCommands = lib.concatStringsSep "\n" (map (
      key: let
        bits =
          if key ? bits
          then "-b ${toString key.bits}"
          else "";
      in ''
        if [ ! -f ${key.path} ]; then
          $DRY_RUN_CMD ${pkgs.openssh}/bin/ssh-keygen -t ${key.type} ${bits} -f ${key.path} -N ""
        fi
      ''
    )
    keys.hostKeys);
in {
  # Environment packages for nix-on-droid (system-level)
  # Uses shared package lists from common/packages.nix
  # Note: User packages are managed via home-manager in home.nix
  environment.packages =
    packages.coreUtils
    ++ packages.compression
    ++ packages.networkTools
    ++ packages.systemTools
    ++ packages.editors;

  # Backup etc files instead of failing to activate generation if a file already exists in /etc
  environment.etcBackupExtension = ".bak";

  # Read the changelog before changing this value
  system.stateVersion = "24.05";

  # Set up nix for flakes
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  # Set your time zone (uncomment and set as needed)
  # time.timeZone = "Asia/Shanghai";

  # Android integration - termux tools
  android-integration = {
    am.enable = true;
    termux-open.enable = true;
    termux-open-url.enable = true;
    termux-setup-storage.enable = true;
    termux-reload-settings.enable = true;
    termux-wake-lock.enable = true;
    termux-wake-unlock.enable = true;
    xdg-open.enable = true;
  };

  # Configure home-manager
  home-manager = {
    config = ./home.nix;
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
    extraSpecialArgs = {
      inherit sshd-start;
    };
  };

  # Set default shell
  user.shell = "${pkgs.zsh}/bin/zsh";

  # SSH host key generation (uses shared hostKeys from keys.nix)
  # Note: sshd_config, authorized_keys, and termux-boot are managed declaratively via home-manager
  build.activation.sshd = ''
    $VERBOSE_ECHO "Setting up sshd host keys..."
    mkdir -p /etc/ssh

    ${hostKeyGenCommands}
  '';
}
