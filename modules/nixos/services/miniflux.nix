{ ... }:
{
  flake.nixosModules.miniflux =
{ config, env, ... }:
let
  fqdn = env.cloudSettings.internal;
  domain = "${env.cloudSettings.services.miniflux.subdomain}.${fqdn}";
  port = env.cloudSettings.services.miniflux.port;
in
{
  services.miniflux = {
    enable = true;

    config = {
      CREATE_ADMIN = 1;
      LISTEN_ADDR = "127.0.0.1:${toString port}";

      HTTPS = 1;
    };

    createDatabaseLocally = true;
    adminCredentialsFile = config.age.secrets.miniflux_admin_pass.path;

  };

  # Nginx
  services.nginx.virtualHosts.${domain} = {
    serverName = domain;

    enableACME = false;
    useACMEHost = fqdn;
    forceSSL = true;

    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://localhost:${toString port}";
      proxyWebsockets = true;

      extraConfig = ''
        proxy_read_timeout   600s;
        proxy_send_timeout   600s;
        send_timeout         600s;
      '';
    };
  };

  # Agenix
  age.secrets = {
    miniflux_admin_pass = {
      file = ../../../secrets/miniflux_admin_pass.age;
    };
  };
}
  ;
}
