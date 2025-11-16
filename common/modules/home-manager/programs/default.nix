# Desktop-specific program configurations
# These are optional modules for GUI environments
# Import via: ../../common/home-manager/programs in desktop configs
{
  imports = [
    ./rime
    ./vscode
    # ./wechat
    ./emacs.nix
    ./firefox
    ./gnome.nix
  ];
}
