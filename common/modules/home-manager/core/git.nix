{pkgs, lib, ...}:
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
        echo "Updated ~/.netrc with GitLab credentials" >&2
      fi
    else
      echo "Failed to get credentials from glab" >&2
      exit 1
    fi
  '';

  # Git wrapper that syncs GitLab credentials before fetch/clone/pull operations
  # This acts as a "pre-fetch hook" for Nix's git fetcher
  gitWithGlabSync = pkgs.writeShellScriptBin "git" ''
    # Check if this is a fetch-like operation that might need GitLab auth
    case "$1" in
      fetch|clone|pull|ls-remote|submodule)
        # Check if any argument contains gitlab.com
        if echo "$@" | grep -q "gitlab.com"; then
          ${glab-netrc-sync}/bin/glab-netrc-sync 2>/dev/null || true
        fi
        ;;
    esac
    exec ${pkgs.git}/bin/git "$@"
  '';
in {
  home.packages = [
    glab-netrc-sync
    # Put git wrapper first in PATH so it's used instead of real git
    (lib.hiPrio gitWithGlabSync)
  ];

  # Note: netrc-file is configured at system level in common-base.nix
  # The git wrapper auto-syncs credentials for GitLab fetches

  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = "main";
      pull.rebase = false;
      submodule.recurse = true;
      user = {
        name = "Bingchen Gong";
        email = "6704443+Wenri@users.noreply.github.com";
      };

      # Use GitLab CLI for GitLab authentication
      credential."https://gitlab.com".helper = "!${pkgs.glab}/bin/glab auth git-credential";
    };
  };
}
