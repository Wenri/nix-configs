{ pkgs, lib, config, hostname, ... }:
let
  # Domain should be configurable per host
  domain = "wenri.me";
  fqdn = "${hostname}.${domain}";
  baseUrl = "https://${fqdn}";
  clientConfig."m.homeserver".base_url = baseUrl;
  serverConfig."m.server" = "${fqdn}:443";
  mkWellKnown = data: ''
    default_type application/json;
    add_header Access-Control-Allow-Origin *;
    return 200 '${builtins.toJSON data}';
  '';
  # Define the database password as a parameter
  dbPassword = "WVlRuZGovPdSSMxZhiznuahgtJxcnVVkGdmZegyBsoVrTBHKvb";
  # Initial SQL script that runs only on first PostgreSQL initialization
  # Sets password for matrix-synapse user and creates database with correct collation
  initSql = pkgs.writeText "matrix-synapse-init.sql" ''
    -- Set password for matrix-synapse user (created by ensureUsers)
    ALTER USER "matrix-synapse" WITH PASSWORD '${dbPassword}';
    
    -- Create database with C collation (required by Synapse)
    -- Note: CREATE DATABASE cannot run in a transaction, but initialScript runs outside transactions
    -- If database already exists, this will fail silently (which is fine for initialScript)
    CREATE DATABASE "matrix-synapse" WITH LC_COLLATE='C' LC_CTYPE='C' TEMPLATE template0 OWNER "matrix-synapse";
  '';
in {
  networking.hostName = hostname;
  networking.domain = domain;
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  security.acme = {
    acceptTerms = true;
    defaults.email = "wenri@wenri.me";
  };

  services.postgresql = {
    enable = true;
    # Don't use ensureDatabases - we create it in initialScript with correct collation
    # Don't use ensureDBOwnership - we set ownership in CREATE DATABASE command
    ensureUsers = [{
      name = "matrix-synapse";
    }];
    # Initial script runs only on first PostgreSQL initialization
    # Sets password and creates database with correct collation and ownership
    initialScript = initSql;
  };

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;
    recommendedProxySettings = true;
    virtualHosts = {
      "${fqdn}" = {
        enableACME = true;
        forceSSL = true;
        locations."/".extraConfig = ''
          return 404;
        '';
        locations."/_matrix".proxyPass = "http://[::1]:8008";
        locations."/_synapse/client".proxyPass = "http://[::1]:8008";
        locations."= /.well-known/matrix/server".extraConfig = mkWellKnown serverConfig;
        locations."= /.well-known/matrix/client".extraConfig = mkWellKnown clientConfig;
      };
    };
  };

  services.matrix-synapse = {
    enable = false;
    settings.server_name = config.networking.domain;
    settings.public_baseurl = baseUrl;
    settings.listeners = [
      { port = 8008;
        bind_addresses = [ "::1" ];
        type = "http";
        tls = false;
        x_forwarded = true;
        resources = [ {
          names = [ "client" "federation" ];
          compress = true;
        } ];
      }
    ];
    settings.database = {
      name = "psycopg2";
      args = {
        database = "matrix-synapse";
        user = "matrix-synapse";
        # Use the same password parameter
        password = dbPassword;
        host = "localhost";
        cp_min = 5;
        cp_max = 10;
      };
    };
    settings.registration_shared_secret = dbPassword;
  };

  # Nginx URL probe protection - blocks automated scanning/probing
  # Only enabled on machines with nginx (this module)
  services.fail2ban.jails = {
    "nginx-url-probe" = {
      settings = {
        enabled = true;
        filter = "nginx-url-probe";
        logpath = "/var/log/nginx/access.log";
        action = "%(action_)s[blocktype=DROP]";
        backend = "auto";  # Required for log file backend
        maxretry = 5;
        findtime = 600;  # 10 minutes
      };
    };
  };

  # Create custom nginx-url-probe filter for fail2ban
  # This filter detects common URL probing patterns (404s, suspicious paths, etc.)
  # Based on analysis of actual attack patterns in nginx access logs
  environment.etc."fail2ban/filter.d/nginx-url-probe.conf" = {
    text = ''
      [Definition]
      # Fail regex patterns for common URL probing attempts
      # Matches requests that return error status codes (404, 403, 400, 500, etc.)
      # and contain suspicious URL patterns
      
      # Patterns (all continuation lines must be indented, no comments between them):
      # 1. Suspicious file extensions
      # 2. Git and config file probing  
      # 3. Path traversal attempts
      # 4. PHP RCE attempts
      # 5. API documentation probing (Swagger, GraphQL)
      # 6. Spring Boot actuator endpoints
      # 7. WordPress probing
      # 8. Laravel probing
      # 9. Confluence/Jira probing
      # 10. Exchange/Outlook probing
      # 11. Router/device probing
      # 12. Debug and info endpoints
      # 13. Docker registry probing
      # 14. SQL injection patterns
      # 15. Command injection patterns
      # 16. XSS patterns
      failregex = ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*\.(php|asp|jsp|cgi|pl|sh|exe|bat|cmd|dll|ini|log|sql|bak|old|tmp|swp|env|git|svn|htaccess|htpasswd|DS_Store).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) (/\.git/|/\.env|/\.vscode/|/config\.json|/config\.php|/admin/config\.php).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(\.\./|\.\.\\|%%2e%%2e|%%2E%%2E|%%%%32%%65).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*phpunit.*eval-stdin.*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) (/graphql|/api/graphql|/api/gql|/graphql/api|/.*swagger|/.*api-docs).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*actuator.*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(wp-admin|wp-login|wp/v2|rest_route).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(telescope|laravel-filemanager|@vite/env).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(login\.action|META-INF/maven).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(owa/auth|ecp/).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(cgi-bin/|server-status|server\.cgi).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(debug/|info\.php|test\.php|version|server).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(v2/_catalog|_all_dbs).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(union.*select|insert.*into|delete.*from|update.*set|drop.*table|create.*table).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(/bin/sh|/bin/bash|/etc/passwd|/proc/self|eval\(|base64|shell|cmd|exec|system|passthru).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(script|javascript|onerror|onload|onclick|alert|document\.cookie).*" (404|403|400|500|502|503)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*(HNAP1|boaform|PictureCatch\.cgi|setup\.cgi|funjsq|\\+CSCO[LE]\+).*" (404|403|400|500|502|503|301|302)
                  ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) .*\\x[0-9A-Fa-f]{2}.*" (404|403|400|500|502|503|301|302)
                  ^<HOST> -.*"\\x[0-9A-Fa-f]{2}.*" (404|403|400|500|502|503)
      
        # Ignore legitimate requests that commonly return 404
        ignoreregex = ^<HOST> -.*"(GET|POST|HEAD|PUT|DELETE|PATCH|OPTIONS) (?:/|/robots\.txt|/favicon\.ico|/\.well-known/security\.txt)(?:\?[^"]*)? HTTP/[0-9.]+" (404|403|400|500|502|503)
    '';
    mode = "0644";
  };
}
