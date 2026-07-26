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

  officeDomain = "${env.cloudSettings.services.onlyoffice.subdomain}.${fqdn}";
  officePort = env.cloudSettings.services.onlyoffice.port;
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

      eurooffice = {
        DocumentServerUrl = "https://${officeDomain}/";
      };
    };

    secretFile = config.age.secrets.onlyoffice_nextcloud_jwt.path;

    configureRedis = true;
    caching.redis = true;

    phpOptions = {
      "opcache.interned_strings_buffer" = "16";
    };
  };

  # OnlyOffice DocumentServer, the backend the eurooffice app talks to.
  # Creates its own postgres db/user, rabbitmq and nginx vhost.
  services.onlyoffice = {
    enable = true;

    hostname = officeDomain;
    port = officePort;

    jwtSecretFile = config.age.secrets.onlyoffice_jwt_secret.path;
    securityNonceFile = config.age.secrets.onlyoffice_nginx_nonce.path;

    # DocumentServer downloads files from Nextcloud, which resolves to this host.
    allowLocalConnections = true;
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

    onlyoffice_jwt_secret = {
      file = ../../../secrets/onlyoffice_jwt_secret.age;
      owner = "onlyoffice";
      group = "onlyoffice";
      mode = "0440";
    };

    onlyoffice_nextcloud_jwt = {
      file = ../../../secrets/onlyoffice_nextcloud_jwt.age;
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0440";
    };

    onlyoffice_nginx_nonce = {
      file = ../../../secrets/onlyoffice_nginx_nonce.age;
      owner = "onlyoffice";
      group = "onlyoffice";
      mode = "0440";
    };
  };

  # Persistence
  environment.persistence."/persist".directories = [
    {
      directory = "/data/nextcloud";
      user = "nextcloud";
      group = "nextcloud";
    }
    {
      directory = "/var/lib/onlyoffice";
      user = "onlyoffice";
      group = "onlyoffice";
    }
    {
      directory = "/var/lib/rabbitmq";
      user = "rabbitmq";
      group = "rabbitmq";
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

  # Locations come from the upstream onlyoffice module; only TLS is added here.
  services.nginx.virtualHosts.${officeDomain} = {
    serverName = officeDomain;

    enableACME = false;
    useACMEHost = fqdn;
    forceSSL = true;
  };

  users.users.nextcloud.uid = 999;
  users.groups.nextcloud.gid = 999;

  # rabbitmq is not pinned here; upstream already fixes it at 85.
  users.users.onlyoffice.uid = 987;
  users.groups.onlyoffice.gid = 987;

  users.users.redis-nextcloud.group = "redis-nextcloud";
  users.groups.redis-nextcloud = {};

  users.users.redis-nextcloud.uid = 994;
  users.groups.redis-nextcloud.gid = 994;
}
  ;
}
