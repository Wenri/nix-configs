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
    gawk
    file
    tree
    less
    bc # calculator
    dos2unix
    watch
  ];

  # Compression tools
  compression = with pkgs; [
    bzip2
    gzip
    xz
    zip
    unzip
    zstd
    p7zip
  ];

  # Network tools
  networkTools = with pkgs; [
    curl
    wget
    openssh
    iproute2 # ip command
    nettools # ifconfig command
    dnsutils # dig, nslookup
    netcat-gnu
    rsync
    aria2
  ];

  # System tools
  # Note: tzdata not needed - time.timeZone creates /etc/zoneinfo symlink
  systemTools = with pkgs; [
    glibc.bin # tzselect, zdump, zic, locale, iconv, etc.
    hostname
    man
    which
    gnupg
    patchelf # use patchelf --print-needed instead of ldd
    ncurses # reset, clear, tput
    htop
    lsof
  ];

  # Editors (neovim only - vim is provided by nixosOnly or home-manager)
  editors = with pkgs; [
    neovim
  ];

  # Modern CLI tools
  modernCli = with pkgs; [
    ripgrep # rg - better grep
    fd # better find
    bat # better cat
    eza # better ls
    fzf # fuzzy finder
    yq # jq for yaml
  ];

  # Development tools (shared)
  devTools = with pkgs; [
    jq
    gnumake
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
