
{ ... }:
{
  flake.nixosModules.calibre =
{ config, lib, pkgs, env, ... }:
let
  fqdn = env.cloudSettings.fqdn;
  domain = "${env.cloudSettings.services.calibre.subdomain}.${fqdn}";

  staticFilesLibrary = "/data/static-files";
in
{
  # Nginx
  services.nginx.virtualHosts.${domain} = {
    serverName = domain;

    enableACME = false;
    useACMEHost = fqdn;
    forceSSL = true;

    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://localhost:${toString port}";

      proxyWebsockets = false;
      extraConfig = ''
        proxy_read_timeout   600s;
        proxy_send_timeout   600s;
        send_timeout         600s;
      '';
    };
  };

  # Persistence
  environment.persistence."/persist".directories = [
    {
      directory = staticFilesLibrary;
      user = "calibre-web";
      group = "calibre-web";
    }
  ];

}
  ;
}
