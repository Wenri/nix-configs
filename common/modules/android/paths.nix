# Centralized path definitions for nix-on-droid (Android)
# These paths are Android-specific and tied to the Termux app package name.
# All nix-on-droid modules should import this file instead of hardcoding paths.
{
  # Base directory for Termux app data
  # This is the Android app's private storage location
  termuxBase = "/data/data/com.termux.nix/files";

  # Installation directory (Nix prefix)
  # Contains /nix/store, /bin, /etc, and other FHS-like directories
  installationDir = "/data/data/com.termux.nix/files/usr";

  # Home directory
  homeDir = "/data/data/com.termux.nix/files/home";

  # Termux environment file location
  termuxEnvFile = "/data/data/com.termux.nix/files/usr/etc/termux/termux.env";
}
