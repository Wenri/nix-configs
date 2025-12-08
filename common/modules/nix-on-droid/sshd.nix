# SSH server module for nix-on-droid
# Provides declarative sshd configuration with host key management
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.sshd;
  keys = import ../../keys.nix;

  # SSH server configuration
  sshdConfig = {
    Port = cfg.port;
    HostKey = map (k: k.path) keys.hostKeys;
    PasswordAuthentication = cfg.passwordAuthentication;
    PubkeyAuthentication = true;
    PrintMotd = true;
  };

  # Convert attrset to sshd_config format
  formatSshdConfig = conf:
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
      conf));

  sshdConfigFile = pkgs.writeText "sshd_config" (formatSshdConfig sshdConfig);

  # Termux-boot script to start sshd
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
  options.services.sshd = {
    enable = lib.mkEnableOption "OpenSSH server for nix-on-droid";

    port = lib.mkOption {
      type = lib.types.port;
      default = 2222;
      description = "Port to listen on (default 2222 to avoid needing root)";
    };

    passwordAuthentication = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to allow password authentication";
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = keys.all;
      description = "List of authorized SSH public keys";
    };
  };

  config = lib.mkIf cfg.enable {
    # Pass sshd-start script to home-manager via extraSpecialArgs
    home-manager.extraSpecialArgs = {
      inherit sshd-start;
      sshdAuthorizedKeys = cfg.authorizedKeys;
    };

    # SSH host key generation activation script
    build.activation.sshd = ''
      $VERBOSE_ECHO "Setting up sshd host keys..."
      mkdir -p /etc/ssh

      ${hostKeyGenCommands}
    '';
  };
}
