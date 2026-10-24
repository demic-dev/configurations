{ ... }:
{
  flake.nixosModules.acme =
{ config, pkgs, env, ... }:
let
  fqdn = env.cloudSettings.fqdn;
  internal = env.cloudSettings.internal;
  email = env.cloudSettings.email;
in
{
  users.users.nginx.extraGroups = ["acme"];

  security.acme = {
    acceptTerms = true;

    defaults = {
      email = email;

      dnsProvider = "cloudflare";
      environmentFile = config.age.secrets.cloudflare_dns_challenge.path;

      dnsPropagationCheck = true;
    };

    certs = {
      ${fqdn} = {
        domain = fqdn;
        extraDomainNames = [
          "*.${fqdn}"
        ];

        group = "nginx";
      };
      ${internal} = {
        domain = internal;
        extraDomainNames = [
          "*.${internal}"
        ];

        group = "nginx";
      };
    };
  };

  # Persistence
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/acme";
      user = "acme";
      group = "nginx";
    }
  ];

  # Agenix
  age.secrets.cloudflare_dns_challenge = {
    file = ../../secrets/cloudflare_dns_challenge.age;
    owner = "acme";
    group = "acme";
    mode = "0400";
  };

  users.users.acme.uid = 998;
  users.groups.acme.gid = 998;
}
  ;
}
