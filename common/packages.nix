# Shared package lists for all hosts
# Usage: import this file with pkgs to get package lists
#   let packages = import ../../common/packages.nix {inherit pkgs;};
#   in packages.coreUtils ++ packages.networkTools
{pkgs}: {
  # Core Unix utilities (needed at system level)
  coreUtils = with pkgs; [
    (lib.hiPrio procps) # Prioritize procps's kill over util-linux's kill
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
    mtr # better traceroute
    socat # socket utility
  ];

  # System tools
  # Note: tzdata not needed - time.timeZone creates /etc/zoneinfo symlink
  # Note: glibc.bin removed - causes conflict with Android glibc on nix-on-droid
  systemTools = with pkgs; [
    hostname
    man
    which
    gnupg
    patchelf # use patchelf --print-needed instead of ldd
    ncurses # reset, clear, tput
    htop
    lsof
    # Debugging and tracing
    strace
    ltrace
    time # command timer
    psmisc # pstree, fuser
    sysstat # sar, iostat, pidstat
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
    jq # JSON processor
    yq # jq for yaml
    delta # better git diff
    difftastic # structural diff
  ];

  # Development tools (shared)
  # Includes key stdenv components for building software
  devTools = with pkgs; [
    # From stdenv
    gnumake
    gcc
    stdenv.cc
    patch
    pkg-config
    binutils # readelf, objdump, strings, nm, ar
    # Build system tools
    autoconf
    automake
    libtool
    cmake
    ninja
    # Debugging
    gdb
  ];

  # Rust toolchain
  rustToolchain = with pkgs; [
    rustc
    cargo
    rust-analyzer
    clippy
    rustfmt
  ];

  # Go toolchain
  goToolchain = with pkgs; [
    go
    gopls
    delve
    go-tools # staticcheck, etc.
  ];

  # NixOS-specific packages (require real system, not proot)
  nixosOnly = with pkgs; [
    vim
    guix # too complex to patch for Android glibc
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
