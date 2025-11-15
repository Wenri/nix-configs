{pkgs, ...}: {
  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = "main";
      pull.rebase = false;
    };
    # Uncomment and configure your git settings
    # userName = "Your Name";
    # userEmail = "your.email@example.com";
  };
}
