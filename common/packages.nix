# Shared package lists for all hosts
# Usage: import this file with pkgs to get package lists
#   let packages = import ../../common/packages.nix {inherit pkgs;};
#   in packages.coreUtils ++ packages.networkTools
{pkgs}: {
  # Core Unix utilities (needed at system level)
  coreUtils = with pkgs; [
    procps
    killall
    diffutils
    findutils
    util-linux
    gnugrep
    gnused
    gnutar
  ];

  # Compression tools
  compression = with pkgs; [
    bzip2
    gzip
    xz
    zip
    unzip
  ];

  # Network tools
  networkTools = with pkgs; [
    curl
    wget
    openssh
  ];

  # System tools
  systemTools = with pkgs; [
    tzdata
    hostname
    man
    which
  ];

  # Editors (neovim only - vim is provided by nixosOnly or home-manager)
  editors = with pkgs; [
    neovim
  ];

  # Development tools (shared)
  devTools = with pkgs; [
    gitMinimal
    jq
  ];

  # NixOS-specific packages (require real system, not proot)
  nixosOnly = with pkgs; [
    vim
    ethtool
    usbutils
    ndisc6
    iputils
    # ping6 wrapper for convenience
    (writeShellScriptBin "ping6" ''
      exec ${iputils}/bin/ping -6 "$@"
    '')
  ];
}
