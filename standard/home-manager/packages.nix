{pkgs, ...}: {
  home.packages = with pkgs; [
    tmux
    gnumake
    element-desktop
    discord
    zoom-us
    teamviewer
    signal-desktop
    elixir
    parted
    slack
    siyuan
    bitwarden-desktop
    google-chrome
    agda
    wechat-uos
  ];
}
