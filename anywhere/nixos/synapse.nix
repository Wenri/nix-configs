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
    enable = true;
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
}
