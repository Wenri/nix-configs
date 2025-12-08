# Locale and timezone configuration for nix-on-droid
# Mirrors common/modules/nixos/locale.nix where applicable
{...}: {
  # Set your time zone (same as NixOS hosts)
  time.timeZone = "Europe/Paris";

  # Note: i18n settings are limited on nix-on-droid/Android
  # Full locale configuration is available on NixOS hosts
}
