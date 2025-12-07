{
  config,
  lib,
  pkgs,
  inputs,
  outputs,
  ...
}: {
  # Environment packages for nix-on-droid
  environment.packages = with pkgs; [
    # User-facing stuff
    vim
    neovim

    # Some common utilities
    procps
    killall
    diffutils
    findutils
    util-linux
    tzdata
    hostname
    man
    gnugrep
    gnused
    gnutar
    bzip2
    gzip
    xz
    zip
    unzip

    # Additional useful tools
    htop
    file
    jq
    ripgrep
    tmux
    openssh
    curl
    wget
    git
    which
  ];

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

  # Configure home-manager
  home-manager = {
    config = ./home.nix;
    backupFileExtension = "hm-bak";
    useGlobalPkgs = true;
  };
}
