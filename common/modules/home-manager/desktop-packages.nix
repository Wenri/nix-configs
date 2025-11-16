# Desktop packages for GUI environments
# Import this module in desktop configurations (like standard/)
# Not imported by default in common/home-manager/default.nix
{pkgs, ...}: {
  home.packages = with pkgs; [
    # Build tools
    gnumake

    # Communication
    element-desktop
    discord
    slack
    signal-desktop

    # Collaboration
    zoom-us
    teamviewer

    # Productivity
    siyuan
    bitwarden-desktop
    parsec-bin

    # Browsers
    google-chrome

    # Social
    wechat-uos

    # Development languages (desktop-focused)
    elixir
    agda
  ];
}
