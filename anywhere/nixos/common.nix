{
  inputs,
  outputs,
  modulesPath,
  lib,
  config,
  pkgs,
  ...
}: {
  nixpkgs.config.allowUnfree = true;

  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Opinionated: disable global registry
      flake-registry = "";
      # Workaround for https://github.com/NixOS/nix/issues/9574
      nix-path = config.nix.nixPath;
    };
    # Opinionated: disable channels
    channel.enable = false;

    # Opinionated: make flake registry and nix path match flake inputs
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
  };

  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
    (modulesPath + "/profiles/qemu-guest.nix")
    ./disk-config.nix
    ./users.nix
  ];

  boot.loader.grub = {
    # no need to set devices, disko will add all devices that have a EF02 partition to the list already
    # devices = [ ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  services.openssh.enable = true;
  services.tailscale.enable = true;
  services.tailscale.useRoutingFeatures = "server";
  services.qemuGuest.enable = true;
  services.fail2ban.enable = true;

  environment.systemPackages = map lib.lowPrio [
    pkgs.curl
    pkgs.gitMinimal
    pkgs.vim
    pkgs.wget
    pkgs.ethtool
    pkgs.usbutils
  ];

  swapDevices = [
    { device = "/swapfile"; size = 2 * 1024; }
  ];

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 30;
  };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCnOOmUOZ9Zbdgoywwpe2cNKvndWTwHGsX+mdCgQwt9dwAqUTYg/TTPdYzM/v6iiB93dEZmcHqjVnWysDaOycbpWSB0utI/qsQcp1QB0xweHFDchQZsLovixIwlilO4gU4jH51KAxdLlhVcoxDgYQ5sKslnhfwbEkbXU2ddzICBTkSGeh7B7wPJUWQqHRle+I7C2AUMkwXO+BaacsxF9dZ7wFRVLOx9EZl4mD+bLi///WJ7jIZR7abx34FGf16Oez4N+GJCLgzpcTnMEga6lXSWYWXq3Udn+4KgvQpwAcLa65c48HcshMi+jnZonroihZ8zr1iNcZgb+LLJYj94nnnM9DIQ6ptMYNnr6Lmlqbx354KYUW+8JD4manmyoQ97mosZE6LneSVYSXfg1burTG51gb117GAWecaTv8rmkJix0+3W/uSRBHar+w6dvLnDfw4wndbo5K4LQqxxn5JxUUS14wcglEmlle4ZfttCdTFf9q9r3kxjip2+PBMr54xVHV7iH+zSDEJk6+u/oOhHSTrc0GfWV9kswpHtAI87FFyJ0/denQcXVU+bg93D8NibYZcFj0DmzwA8qae5rRYPXEMHEV2TU+5OrinxV3ySkVETcUFIuOGewBf9PlwgXQMmYiS5f4+ZpZyUd9TdmfXOGlRDySn0MPjV4gwgRXfq06lKFQ=="
  ];

  virtualisation.docker.enable = true;

  # Enable systemd-oomd for OOM handling
  systemd.oomd.enable = true;

  # Enable passwordless sudo for wheel group
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "24.11";
}
