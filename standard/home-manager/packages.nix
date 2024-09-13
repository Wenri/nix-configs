{pkgs, ...}: {
  home.packages = with pkgs; [
    tmux
    gnumake
    element-desktop
    discord
    zoom-us
    teamviewer
  ];
}
