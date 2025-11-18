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

    # Development tools
    gnumake
    nodejs
    glab

    # AI assistants and tools
    claude-code
    cursor-cli
    gemini-cli
  ];
}
