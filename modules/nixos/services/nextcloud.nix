{ ... }:
{
  flake.nixosModules.nextcloud =
{ self, config, pkgs, env, ... }:
let
  fqdn = env.cloudSettings.fqdn;
  domain = "${env.cloudSettings.services.nextcloud.subdomain}.${env.cloudSettings.fqdn}";
  port = env.cloudSettings.services.nextcloud.port;
  redisPort = port + 1;
  maxUploadSize = env.cloudSettings.services.nextcloud.maxUploadSize;
  client_max_body_size = env.cloudSettings.services.nextcloud.client_max_body_size;
in
{
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud34;

    hostName = domain;
    https = true;

    database.createLocally = true;
    maxUploadSize = maxUploadSize;

    datadir = "/data/nextcloud";
    home = "/data/nextcloud";

    extraAppsEnable = true;
    extraApps =  {
      inherit (config.services.nextcloud.package.packages.apps)
      calendar
      contacts
      ;
      eurooffice = pkgs.fetchNextcloudApp {
        url = "https://github.com/nextcloud-releases/eurooffice/releases/download/v11.0.1/eurooffice-v11.0.1.tar.gz";
        hash = "sha256-HXpvyCNhlxAvrxSEu6/5u0mpg7TrTsaS2gii9mf74ns=";
        license = "agpl3Only";
      };
    };

    config = {
      dbtype = "pgsql";
      dbhost = "/run/postgresql";
      dbuser = "nextcloud";
      dbname = "nextcloud";

      adminpassFile = config.age.secrets.nextcloud_root_pass.path;
      adminuser = "root";
    };

    settings = {
      overwriteprotocol = "https";
      default_phone_region = "IT";

      mail_smtpmode = "sendmail";
      mail_sendmailmode = "pipe";

      maintenance_window_start = 1;
    };

    configureRedis = true;
    caching.redis = true;

    phpOptions = {
      "opcache.interned_strings_buffer" = "16";
    };
  };

  # Postgres
  services.postgresql = {
    ensureDatabases = [ "nextcloud" ];
    ensureUsers = [
      {
        name = "nextcloud";
        ensureDBOwnership = true;
      }
    ];
  };

  services.postgresqlBackup = {
    enable = true;
    location = "/home/.backups/postgres/nextcloud";
    databases = [ "nextcloud" ];
    startAt = "*-*-* 03:15:00";
  };

  # Redis
  services.redis.servers.nextcloud = {
    enable = true;
    port = redisPort;
    bind = "127.0.0.1";
  };

  # Agenix
  age.secrets = {
    nextcloud_root_pass = {
      file = ../../../secrets/nextcloud_root_pass.age;
      owner = "nextcloud";
      group = "nextcloud";
    };
  };

  # Persistence
  environment.persistence."/persist".directories = [
    {
      directory = "/data/nextcloud";
      user = "nextcloud";
      group = "nextcloud";
    }
  ];

  # Fail2Ban Jail
   services.fail2ban.jails.nextcloud.settings = {
     filter = "nextcloud";
     backend = "auto";
     findtime = 86400;
     bantime  = 43200;
     maxretry = 5;
  };

  environment.etc."fail2ban/filter.d/nextcloud.conf".text = pkgs.lib.mkDefault( pkgs.lib.mkAfter ''
    [Definition]
    _groupsre = (?:(?:,?\s*"\w+":(?:"[^"]+"|\w+))*)
    failregex = ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Login failed:
            ^\{%(_groupsre)s,?\s*"remoteAddr":"<HOST>"%(_groupsre)s,?\s*"message":"Trusted domain error.
    datepattern = ,?\s*"time"\s*:\s*"%%Y-%%m-%%d[T ]%%H:%%M:%%S(%%z)?"
  '');

  systemd = {
    services."nextcloud-setup" = {
      requires = [ "postgresql.service" ];
      after = [ "postgresql.service" ];
    };
  };

  # Nginx
  services.nginx.virtualHosts.${domain} = {
    serverName = domain;

    enableACME = false;
    useACMEHost = fqdn;
    forceSSL = true;

    locations."/$request_uri" = {
      recommendedProxySettings = true;
      proxyPass = "http://localhost:${builtins.toString port}";
      proxyWebsockets = true;

      extraConfig = ''
      	client_max_body_size ${client_max_body_size};
        proxy_read_timeout   600s;
        proxy_send_timeout   600s;
        send_timeout         600s;
      '';
    };
  };

  users.users.nextcloud.uid = 999;
  users.groups.nextcloud.gid = 999;

  users.users.redis-nextcloud.group = "redis-nextcloud";
  users.groups.redis-nextcloud = {};

  users.users.redis-nextcloud.uid = 994;
  users.groups.redis-nextcloud.gid = 994;
}
  ;
}
