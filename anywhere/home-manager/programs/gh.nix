{pkgs, ...}: {
  programs.gh = {
    enable = true;
    # Settings can be configured here
    # Authentication is done via: gh auth login
    settings = {
      # You can add default settings here
      # For example:
      # git_protocol = "ssh";
      # editor = "vim";
    };
  };
}
