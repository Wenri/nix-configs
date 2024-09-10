{pkgs, ...}: {

  dconf.settings = {
    "org/gnome/shell" = {
      enabled-extensions = [
        "kimpanel@kde.org"
      ];
    };
  };

  home.packages = with pkgs;
  with gnome;
  with gnomeExtensions; [
    kimpanel
  ];

}
