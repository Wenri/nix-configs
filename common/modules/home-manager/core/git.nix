{pkgs, ...}: {
  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = "main";
      pull.rebase = false;
      user = {
        name = "Bingchen Gong";
        email = "6704443+Wenri@users.noreply.github.com";
      };

      # Use GitLab CLI for GitLab authentication
      credential."https://gitlab.com".helper = "!${pkgs.glab}/bin/glab auth git-credential";
    };
  };
}
