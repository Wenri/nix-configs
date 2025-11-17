# Desktop-specific packages + program configurations
# These are optional modules for GUI environments
# Import via: outputs.homeManagerModules.desktop.default in desktop configs
{
  imports = [
    ./packages.nix
    ./rime
    ./vscode
    # ./wechat
    ./emacs.nix
    ./firefox
    ./gnome.nix
  ];
}
