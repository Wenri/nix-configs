{
  pkgs,
  lib,
  config,
  ...
}: {
  # This value determines the Home Manager release that your
  # configuration is compatible with.
  home.stateVersion = "24.05";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  # Packages to install via home-manager
  home.packages = with pkgs; [
    # Terminal multiplexer
    tmux

    # System utilities
    htop
    file
    jq
    ripgrep

    # Development tools
    gnumake
    nodejs

    # AI assistants
    claude-code
    cursor-cli
  ];

  # ZSH configuration
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -l";
      update = "nix-on-droid switch --flake ~/.config/nix-on-droid";
    };

    history = {
      size = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    oh-my-zsh = {
      enable = true;
      plugins = ["git"];
      theme = "robbyrussell";
    };
  };

  # Git configuration (simplified for nix-on-droid, no 1password signing)
  programs.git = {
    enable = true;
    settings = {
      user.name = "Bingchen Gong";
      user.email = "6704443+Wenri@users.noreply.github.com";
      init.defaultBranch = "main";
      pull.rebase = false;
    };
  };

  # fzf for fuzzy finding
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
}
