{ pkgs, lib, config, ... }:
let
  fqdn = "${config.networking.hostName}.${config.networking.domain}";
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
in {
  networking.hostName = "matrix";
  networking.domain = "wenri.me";
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  security.acme = {
    acceptTerms = true;
    defaults.email = "wenri@wenri.me";
  };

  services.postgresql = {
    enable = true;
    ensureDatabases = [ "matrix-synapse" ];
    ensureUsers = [{
      name = "matrix-synapse";
      ensureDBOwnership = true;
      # Use the password parameter
      password = dbPassword;
    }];
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
  };
}
