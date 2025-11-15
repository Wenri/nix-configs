{pkgs, ...}: {
  home.packages = with pkgs; [
    tmux
    parted
    htop
    nodejs
    claude-code
    cursor-cli
    file
    jq
    iperf3
  ];
}
