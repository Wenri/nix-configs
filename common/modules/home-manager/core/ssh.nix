{
  programs.ssh = {
    enable = true;
    # Disable deprecated default config
    enableDefaultConfig = false;
    matchBlocks = {
      "github.com" = {
        hostname = "ssh.github.com";
        port = 443;
        user = "git";
      };
      # Set defaults explicitly (replacing deprecated default config)
      "*" = {
        addKeysToAgent = "yes";
      };
    };
  };
}
