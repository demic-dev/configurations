{ ... }:
{
  flake.nixosModules.ghost =
{ config, pkgs, env, inputs, lib, ... }:
let
  serviceName = "storiedisilicio";
  serviceDb = "${serviceName}-db";
  serviceNetwork = "${serviceName}-network";

  fqdn = env.cloudSettings.fqdn;
  domain = "${serviceName}.${env.cloudSettings.fqdn}";

  port = 41921;
in
{
  systemd.tmpfiles.rules = [
    "d /var/lib/${serviceName} 0755 root root -"
    "d /var/lib/${serviceDb} 0755 root root -"
  ];
  
  systemd.services."init-${serviceNetwork}" = {
    description = "Create ${serviceName} Docker network";
    after = [ "network.target" "docker.service" ];
    requires = [ "docker.service" ];
    before = [ "docker-${serviceDb}.service" "docker-${serviceName}.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # The '-' prefix ignores the exit code if the network already exists
      ExecStart = "-${pkgs.docker}/bin/docker network create ${serviceNetwork}";
    };
  };

  # NixOS native way to run docker containers
  virtualisation.oci-containers = {
    containers = {
      ${serviceDb} = {
        # Ghost recommends MySQL 8
        image = "mysql:8.0";
        environmentFiles = [ config.age.secrets.ghost-storiedisilicio-db-env.path ];
        volumes = [
          "/var/lib/${serviceDb}:/var/lib/mysql"
        ];
        extraOptions = [ "--network=${serviceNetwork}" ];
      };

      ${serviceName} = {
        image = "ghost:latest";
        ports = [ "${toString port}:2368" ];
        
        environmentFiles = [ config.age.secrets.ghost-storiedisilicio-env.path ];
        environment = {
          # Using the domain instead of localhost
          url = "https://${domain}"; 
          database__client = "mysql";
          # Resolves via the custom docker network
          database__connection__host = serviceDb;
        };

        volumes = [
          "/var/lib/${serviceName}:/var/lib/ghost/content"
        ];
        extraOptions = [ "--network=${serviceNetwork}" ];
      };
    };
  };

  # Nginx reverse proxy
  services.nginx.virtualHosts.${domain} = {
    serverName = domain;

    enableACME = false;
    useACMEHost = fqdn;
    forceSSL = true;

    locations."/" = {
      recommendedProxySettings = true;

      proxyPass = "http://localhost:${toString port}";
      proxyWebsockets = true;
    };
  };

  # Adding to the generic Borg job. It backs up from the /persist snapshot bind-mounted
  # at /var/tmp/borgjobs, so paths must carry that prefix (keep in sync with backup.nix's
  # mountDirectory). listOf paths from multiple modules concatenate automatically.
  services.borgbackup.jobs."generic".paths = [
    "/var/tmp/borgjobs/var/lib/${serviceName}"
    "/var/tmp/borgjobs/var/lib/${serviceDb}"
  ];

  # Persistence
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/${serviceName}";
      user = "root";
      group = "root";
    }
    {
      directory = "/var/lib/${serviceDb}";
      user = "root";
      group = "root";
    }
  ];

  # Agenix
  age.secrets = {
    ghost-storiedisilicio-db-env = {
      file = ../../../secrets/ghost-storiedisilicio-db-env.age;
    };
    ghost-storiedisilicio-env = {
      file = ../../../secrets/ghost-storiedisilicio-env.age;
    };
  };
}

  ;
}
