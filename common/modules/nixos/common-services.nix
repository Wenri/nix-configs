{
  lib,
  ...
}: {
  services.openssh = {
    enable = lib.mkDefault true;
    startWhenNeeded = lib.mkDefault false;
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
    };
  };

  services.tailscale.enable = lib.mkDefault true;

  # Enable fail2ban for all machines to protect against brute force attacks
  services.fail2ban = {
    enable = lib.mkDefault true;

    # IP addresses/subnets to ignore (never ban)
    # Tailscale uses 100.64.0.0/10 (CGNAT range) for its network
    ignoreIP = [
      "100.64.0.0/10"  # Tailscale IPv4 subnet
    ];

    # Configure jails
    jails = {
      # SSH protection - most important for remote servers
      sshd = {
        settings = {
          filter = "sshd";
          maxretry = 5;
          bantime = 3600;  # 1 hour
          findtime = 600;  # 10 minutes
        };
      };

      # Protect against repeated authentication failures
      recidive = {
        settings = {
          filter = "recidive";
          action = "%(action_)s";
          bantime = 604800;  # 1 week
          findtime = 86400;   # 1 day
          maxretry = 5;
        };
      };
    };
  };
}
