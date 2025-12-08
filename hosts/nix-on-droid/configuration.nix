{
  config,
  lib,
  pkgs,
  inputs,
  outputs,
  ...
}: let
  sshd-start = pkgs.writeShellScript "start-sshd" ''
    exec ${pkgs.openssh}/bin/sshd -f $HOME/.ssh/sshd_config
  '';
in {
  # Environment packages for nix-on-droid (system-level)
  # Note: User packages are managed via home-manager in home.nix
  environment.packages = with pkgs; [
    # Editors (neovim for nix-on-droid, vim via home-manager)
    neovim

    # Core utilities required at system level
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

    # Network and system tools
    openssh
    curl
    wget
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

  # Set default shell
  user.shell = "${pkgs.zsh}/bin/zsh";

  # SSH server setup on port 2222
  build.activation.sshd = ''
    $VERBOSE_ECHO "Setting up sshd..."
    mkdir -p $HOME/.ssh

    # Generate host keys if they don't exist
    if [ ! -f $HOME/.ssh/ssh_host_ed25519_key ]; then
      $DRY_RUN_CMD ${pkgs.openssh}/bin/ssh-keygen -t ed25519 -f $HOME/.ssh/ssh_host_ed25519_key -N ""
    fi
    if [ ! -f $HOME/.ssh/ssh_host_rsa_key ]; then
      $DRY_RUN_CMD ${pkgs.openssh}/bin/ssh-keygen -t rsa -b 4096 -f $HOME/.ssh/ssh_host_rsa_key -N ""
    fi

    # Create sshd_config
    $DRY_RUN_CMD cat > $HOME/.ssh/sshd_config << 'EOF'
Port 2222
HostKey ~/.ssh/ssh_host_ed25519_key
HostKey ~/.ssh/ssh_host_rsa_key
AuthorizedKeysFile .ssh/authorized_keys
PasswordAuthentication no
PubkeyAuthentication yes
PrintMotd yes
EOF

    # Setup termux-boot to start sshd on boot
    mkdir -p $HOME/.termux/boot
    ln -sf ${sshd-start} $HOME/.termux/boot/start-sshd
  '';
}
