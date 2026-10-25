{ ... }:
{
  flake.nixosModules.nextcloud =
{ self, config, pkgs, env, ... }:
let
  internal = env.cloudSettings.internal;
  domain = "${env.cloudSettings.services.nextcloud.subdomain}.${internal}";
  port = env.cloudSettings.services.nextcloud.port;
  redisPort = port + 1;
  maxUploadSize = env.cloudSettings.services.nextcloud.maxUploadSize;
  client_max_body_size = env.cloudSettings.services.nextcloud.client_max_body_size;

  officeDomain = "${env.cloudSettings.services.onlyoffice.subdomain}.${internal}";
  officePort = env.cloudSettings.services.onlyoffice.port;

  fqdn = env.cloudSettings.fqdn;
  publicDomain = "${env.cloudSettings.services.nextcloud.subdomain}.${fqdn}";

  # Through the internal vhost: the public Host on 127.0.0.1 would land on the catch-all.
  publicLocation = methods: {
    proxyPass = "https://127.0.0.1";
    recommendedProxySettings = false;
    extraConfig = ''
      limit_except ${methods} { deny all; }
      proxy_ssl_server_name on;
      proxy_ssl_name ${domain};
      proxy_set_header Host ${domain};
      proxy_set_header X-Forwarded-Host $host;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_request_buffering off;
      client_max_body_size ${client_max_body_size};
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
      send_timeout 600s;
    '';
  };
in
{
  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud35;

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
      # occ and cron build absolute URLs from this; the installer left http://localhost.
      "overwrite.cli.url" = "https://${domain}";
      default_phone_region = "IT";

      # The public vhost proxies from 127.0.0.1 with the public host and the visitor's IP.
      trusted_domains = [ publicDomain ];
      trusted_proxies = [ "127.0.0.1" ];
      forwarded_for_headers = [ "HTTP_X_FORWARDED_FOR" ];
      # Cloudflare refuses bodies over 100 MB; the default chunk is 100 MiB.
      "files.chunked_upload.max_size" = 50 * 1024 * 1024;

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
      file = ../../secrets/nextcloud_root_pass.age;
      owner = "nextcloud";
      group = "nextcloud";
    };

    onlyoffice_jwt_secret = {
      file = ../../secrets/onlyoffice_jwt_secret.age;
      owner = "onlyoffice";
      group = "onlyoffice";
      mode = "0440";
    };

    onlyoffice_nextcloud_jwt = {
      file = ../../secrets/onlyoffice_nextcloud_jwt.age;
      owner = "nextcloud";
      group = "nextcloud";
      mode = "0440";
    };

    onlyoffice_nginx_nonce = {
      file = ../../secrets/onlyoffice_nginx_nonce.age;
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
    useACMEHost = internal;
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

  # Public: share links only; office files stay download-only, the document server is internal.
  services.nginx.virtualHosts.${publicDomain} = {
    serverName = publicDomain;

    enableACME = false;
    useACMEHost = fqdn;
    forceSSL = true;

    root = config.services.nginx.virtualHosts.${domain}.root;

    # Only Cloudflare passes ssl_verify_client, and it sets CF-Connecting-IP itself.
    extraConfig = ''
      allow all;
      ssl_verify_client on;
      set_real_ip_from 0.0.0.0/0;
      set_real_ip_from ::/0;
      real_ip_header CF-Connecting-IP;

      # proxy_pass forwards the raw URI and Nextcloud's router doesn't resolve dot segments,
      # so /ocm/../s/x would pass as /s/x here and reach /ocm/{ocmPath} there.
      if ($request_uri ~* "(/|%2f)(\.|%2e)(\.|%2e)?(/|%2f|\?|$)") { return 404; }
    '';

    locations = {
      "/".return = "404";

      # Share page, password form, downloads, previews, and the text, PDF and theming routes it calls.
      # No {n} quantifiers: nixpkgs' config formatter splits them into blocks.
      "~ ^/(index\\.php/)?(s/[\\w-]+(/.*)?|csrftoken|core/mimeicon|apps/files_sharing/publicpreview/[\\w-]+|apps/files_pdfviewer/|apps/text/(public/.+|image|media|mediaPreview|attachments)|apps/theming/(theme|img|image|icon|favicon)(/.*)?)$" = publicLocation "GET POST PUT";
      # Listing, downloads and file drop uploads.
      "~ ^/public\\.php/dav/(files|uploads)/[\\w-]+(/.*)?$" = publicLocation "GET PUT PROPFIND MKCOL MOVE COPY DELETE";

      # Frontend assets straight from the webroot, so a route that only ends in .js never reaches PHP.
      # After the proxied regexes: theming generates some of its images.
      "~ ^/(core/(css|js|img|fonts|l10n)|dist|apps/[\\w-]+/(js|css|img|fonts|l10n))/.+\\.(css|js|mjs|map|json|svg|png|jpe?g|gif|webp|ico|ttf|otf|woff2?|bcmap|ftl|pfb|icc|wasm)$" = {
        priority = 1100;
        extraConfig = ''
          limit_except GET { deny all; }
          try_files $uri =404;
        '';
      };
    };
  };

  # Locations come from the upstream onlyoffice module; only TLS is added here.
  services.nginx.virtualHosts.${officeDomain} = {
    serverName = officeDomain;

    enableACME = false;
    useACMEHost = internal;
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
