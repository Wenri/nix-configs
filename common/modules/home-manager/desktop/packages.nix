# Desktop packages for GUI environments
# Import via outputs.homeManagerModules.desktop.packages in desktop configs
{pkgs, ...}: {
  home.packages = with pkgs; [
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
  ];
}
