{
  lib,
  ...
}: {
  imports = [./common-base.nix];

  networking.networkmanager.enable = lib.mkDefault true;

  services.xserver.enable = lib.mkDefault true;
  services.xserver.xkb = {
    layout = lib.mkDefault "us";
    variant = lib.mkDefault "";
  };

  services.printing.enable = lib.mkDefault true;

  services.pulseaudio.enable = lib.mkDefault false;
  security.rtkit.enable = lib.mkDefault true;
  services.pipewire = {
    enable = lib.mkDefault true;
    alsa.enable = lib.mkDefault true;
    alsa.support32Bit = lib.mkDefault true;
    pulse.enable = lib.mkDefault true;
  };

  services.zfs.autoScrub.enable = lib.mkDefault true;
}
