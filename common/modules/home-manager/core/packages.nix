{pkgs, ...}: {
  # Packages here are in addition to common/packages.nix (imported by common-base.nix)
  # Avoid duplicates - htop, file, jq, ripgrep, fzf, gnumake are already there
  home.packages = with pkgs; [
    # System utilities (tmux enabled via programs.tmux, fzf via programs.fzf)
    parted
    iperf3

    # Editors
    vim

    # Development tools
    nodejs
    glab

    # AI assistants and tools
    claude-code
    cursor-cli
    gemini-cli
    # github-copilot-cli
  ];
}
