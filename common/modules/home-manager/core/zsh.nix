{config, ...}: {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    shellAliases = {
      ll = "ls -l";
    };

    # Auto-sync GitLab credentials before nix commands
    initContent = ''
      # Wrapper to sync GitLab auth before nix commands that may need it
      nixos-rebuild() {
        glab-netrc-sync 2>/dev/null || true
        command nixos-rebuild "$@"
      }

      nix() {
        # Only sync for commands that might fetch from GitLab
        case "$1" in
          build|develop|flake|run|shell|eval)
            glab-netrc-sync 2>/dev/null || true
            ;;
        esac
        command nix "$@"
      }
    '';

    history = {
      size = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
    };

    oh-my-zsh = {
      enable = true;
      plugins = ["git"];
      theme = "robbyrussell";
    };
  };
}
