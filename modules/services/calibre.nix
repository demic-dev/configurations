{ ... }:
{
  flake.nixosModules.calibre =
{ env, ... }:
let
  fqdn = env.cloudSettings.fqdn;
  domain = "${env.cloudSettings.services.calibre.subdomain}.${fqdn}";

  internalFqdn = env.cloudSettings.internal;
  internalDomain = "${env.cloudSettings.services.calibre.subdomain}.${internalFqdn}";

  port = env.cloudSettings.services.calibre.port;
  calibreLibrary = "/data/nextcloud/data/micheledecillis/files/calibre";
in
{
  services.calibre-web = {
    enable = true;
    listen.port = port;

    options = {
      # Using NextCloud library!
      calibreLibrary = calibreLibrary;
      enableBookUploading = true;
    };
  };

  # Nginx
  # Only the OPDS feed is public, for KOReader on the Kindle.
  services.nginx.virtualHosts.${domain} = {
    serverName = domain;

    enableACME = false;
    useACMEHost = fqdn;
    forceSSL = true;

    extraConfig = ''
      allow all;
    '';

    locations."/".return = "404";
    locations."/opds" = {
      recommendedProxySettings = true;
      proxyPass = "http://[::1]:${toString port}";
    };
  };

  services.nginx.virtualHosts.${internalDomain} = {
    serverName = internalDomain;

    enableACME = false;
    useACMEHost = internalFqdn;
    forceSSL = true;

    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://[::1]:${toString port}";

      proxyWebsockets = true;
      extraConfig = ''
        client_max_body_size 50000M;
        proxy_read_timeout   600s;
        proxy_send_timeout   600s;
        send_timeout         600s;
      '';
    };
  };

  # Persistence
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/calibre-web";
      user = "calibre-web";
      group = "calibre-web";
    }
    # calibreLibrary already persisted under /data/nextcloud
  ];

  users.users.calibre-web.uid = 991;
  users.groups.calibre-web.gid = 989;

  users.groups.nextcloud.members = [
    "nextcloud"
    "calibre-web"
  ];
}
  ;
}
