{
  inputs,
  outputs,
  lib,
  pkgs,
  config,
  username,
  ...
}: let
  flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  packages = import ../../packages.nix {inherit pkgs;};
  isX86_64 = pkgs.stdenv.hostPlatform.isx86_64;
in {
  imports = [
    ./common-services.nix
  ];

  # Performance kernel parameters shared across all NixOS hosts
  boot.kernelParams = [
    "iommu.passthrough=1"
    "transparent_hugepage=always"
    "nowatchdog"
    "nmi_watchdog=0"
    "nosoftlockup"
  ] ++ lib.optionals isX86_64 [
    "iommu=pt"
    "mce=dont_log_ce"
    "tsc=nowatchdog"
    "preempt=full"
  ];

  # Root filesystem mount options for ext4 performance
  fileSystems."/".options = lib.unique [
    "discard"
    "lazytime"
    "noauto_da_alloc"
    "nobarrier"
    "noatime"
  ];

  # System packages shared across NixOS hosts
  # Uses shared package lists from common/packages.nix
  environment.systemPackages = lib.mkBefore (map lib.lowPrio (
    packages.coreUtils
    ++ packages.compression
    ++ packages.networkTools
    ++ packages.systemTools
    ++ packages.editors
    ++ packages.modernCli
    ++ packages.devTools
    ++ packages.nixosOnly
  ));

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      inputs.claude-code-nix.overlays.default
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
      outputs.overlays.master-packages
      inputs.nur.overlays.default
      inputs.nix-vscode-extensions.overlays.default
    ];
    config.allowUnfree = lib.mkDefault true;
  };

  security.polkit.enable = true;

  # Allow user services to run without an active login session
  users.users.${username}.linger = true;

  # Enable user tmpfiles for cleanup of temporary directories
  systemd.user.services.systemd-tmpfiles-setup.wantedBy = ["default.target"];
  systemd.user.timers.systemd-tmpfiles-clean.wantedBy = ["timers.target"];

  # Docker with rootless mode for all hosts
  virtualisation.docker.enable = true;
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  nix = {
    settings = {
      experimental-features = "nix-command flakes";
      flake-registry = "";
      nix-path = config.nix.nixPath;
      # Use netrc for GitLab authentication (synced from glab via glab-netrc-sync)
      netrc-file = "/home/${username}/.netrc";
    };
    channel.enable = false;
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };
}
