{pkgs, ...}: {
  home.packages = with pkgs; [
    tmux
    firefox
    gnumake
    element-desktop
  ];

}