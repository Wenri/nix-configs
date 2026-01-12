{pkgs, ...}:
let
  # Script to sync GitLab credentials from glab to netrc for Nix
  glab-netrc-sync = pkgs.writeShellScriptBin "glab-netrc-sync" ''
    set -e
    CREDS=$(echo -e "host=gitlab.com\nprotocol=https\n" | ${pkgs.glab}/bin/glab auth git-credential get 2>/dev/null)
    if [ -n "$CREDS" ]; then
      PASSWORD=$(echo "$CREDS" | grep "^password=" | cut -d= -f2)
      if [ -n "$PASSWORD" ]; then
        echo "machine gitlab.com login oauth2 password $PASSWORD" > ~/.netrc
        chmod 600 ~/.netrc
        echo "Updated ~/.netrc with GitLab credentials"
      fi
    else
      echo "Failed to get credentials from glab" >&2
      exit 1
    fi
  '';
in {
  home.packages = [ glab-netrc-sync ];

  # Note: netrc-file is configured at system level in common-base.nix
  # Run 'glab-netrc-sync' to update ~/.netrc with GitLab credentials

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
