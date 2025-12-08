{pkgs, ...}: {
  home.packages = with pkgs; [
    # Terminal multiplexer
    tmux

    # System utilities
    parted
    htop
    file
    jq
    iperf3
    ripgrep
    fzf

    # Development tools
    gnumake
    nodejs
    glab

    # AI assistants and tools
    claude-code
    cursor-cli
    gemini-cli
  ];

  # Fuzzy finder with shell integration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
}
