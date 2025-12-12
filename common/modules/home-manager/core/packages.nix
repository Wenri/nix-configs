{
  pkgs,
  lib,
  patchPackageForAndroidGlibc ? null,
  ...
}: {
  home.packages = with pkgs; [
    # System utilities (tmux enabled via programs.tmux)
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
    # guix  # Disabled: too complex to patch for Android glibc

    # AI assistants and tools
    claude-code
    cursor-cli
    gemini-cli
    github-copilot-cli
  ];

  # Fuzzy finder with shell integration
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };
}
