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
      # Wrapper handles 'erase' operation gracefully (glab doesn't support erase)
      credential."https://gitlab.com".helper = "!${pkgs.writeShellScript "glab-git-credential" ''
        # Read the operation (first line from stdin)
        read -r operation
        
        # If operation is 'erase', silently ignore it (glab doesn't support erase)
        if [ "$operation" = "erase" ]; then
          # Read and discard the rest of the input (key=value pairs until blank line)
          while IFS= read -r line; do
            [ -z "$line" ] && break
          done
          exit 0
        fi
        
        # For 'get' and 'store', pass everything through to glab
        # First echo the operation, then pass through the rest of stdin
        {
          echo "$operation"
          cat
        } | ${pkgs.glab}/bin/glab auth git-credential "$operation"
      ''}";
    };
  };
}
