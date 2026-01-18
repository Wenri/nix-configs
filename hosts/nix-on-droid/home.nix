# Home-manager configuration for nix-on-droid
# Minimal host-specific config - shared modules provide most functionality
{
  lib,
  pkgs,
  outputs,
  hostname,
  username,
  sshd-start ? null,
  sshdAuthorizedKeys ? [],
  ...
}: let
  keys = import ../../common/keys.nix;
  androidPaths = outputs.androidModules.paths;
in {
  # Import shared core modules
  imports = [
    outputs.homeModules.core.default
  ];

  # Add Rust and Go toolchains (full development module has NUR deps)
  home.packages = with pkgs; [
    # Rust
    rustc cargo rust-analyzer clippy rustfmt
    # Go
    go gopls delve go-tools
  ];

  # Home Manager release compatibility
  home.stateVersion = "24.05";

  # Disable manpage generation - Python multiprocessing fails on Android
  # due to seccomp blocking sem_open syscall
  manual.manpages.enable = false;

  # Global environment variables for Go binaries
  # Go makes direct syscalls that bypass fakechroot, so we need:
  # - SSL certs at real nix store path (not symlinks)
  # - CGO DNS resolver (Go's pure-Go resolver can't read /etc/resolv.conf)
  home.sessionVariables = {
    SSL_CERT_FILE = "${androidPaths.installationDir}${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
    SSL_CERT_DIR = "${androidPaths.installationDir}${pkgs.cacert}/etc/ssl/certs";
    GODEBUG = "netdns=cgo";
  };

  # Declarative SSH authorized_keys and termux-boot
  home.file = lib.mkMerge [
    {
      ".ssh/authorized_keys".text = lib.concatStringsSep "\n" (
        if sshdAuthorizedKeys != []
        then sshdAuthorizedKeys
        else keys.all
      );
    }
    (lib.mkIf (sshd-start != null) {
      ".termux/boot/start-sshd".source = sshd-start;
    })
  ];

  # nix-on-droid specific shell configuration
  programs.zsh = {
    shellAliases = {
      update = "nix-on-droid switch --flake ~/.config/nix-on-droid";
      sshd-start = "~/.termux/boot/start-sshd";
      sshd-stop = "pkill -f 'sshd -f'";
    };

    # Source Android environment variables for SSH sessions
    # login-inner only runs in Termux app, so SSH sessions miss these vars
    # envExtra runs for ALL zsh instances (login, interactive, scripts)
    envExtra = ''
      # Source Android environment variables if not already set
      # (termux.env is captured by nix-on-droid from the original environment)
      if [ -z "$ANDROID_ROOT" ] && [ -f "${androidPaths.termuxEnvFile}" ]; then
        eval "$(${pkgs.gnugrep}/bin/grep -v -E '^export (PATH|HOME|USER|TMPDIR|LANG|TERM)=' "${androidPaths.termuxEnvFile}")"
      fi
    '';
  };
}
