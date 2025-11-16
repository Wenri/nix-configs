# Base CLI packages shared across minimal and anywhere configurations
# These are essential command-line tools for development and system management
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

    # Development tools
    nodejs

    # AI assistants and tools
    claude-code
    cursor-cli
    gemini-cli
  ];
}
