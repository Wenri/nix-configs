{pkgs, ...}: {
  home.packages = with pkgs; [
    tmux
    gnumake
    element-desktop
    discord
    zoom-us
    teamviewer
    signal-desktop
    elixir_1_15
    parted
  ];
}
