{ ... }:
{
  flake.nixosModules.immich =
{ pkgs, env, ... }:
let
  fqdn = env.cloudSettings.fqdn;
  domain = "${env.cloudSettings.services.immich.subdomain}.${fqdn}";

  internalFqdn = env.cloudSettings.internal;
  internalDomain = "${env.cloudSettings.services.immich.subdomain}.${internalFqdn}";

  port = env.cloudSettings.services.immich.port;
  redisPort = port + 1;

  mountPoint = "/var/tmp/immich-borgbase";

  immichPath = "/data/immich";

  proxyLocation = maxBodySize: {
    recommendedProxySettings = true;
    proxyPass = "http://127.0.0.1:${toString port}";
    proxyWebsockets = true;
    extraConfig = ''
      proxy_request_buffering off;
      client_body_buffer_size 1024k;
      client_max_body_size ${maxBodySize};
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
      send_timeout 600s;
    '';
  };
in
{
  services.immich = {
    enable = true;
    package = pkgs.immich;

    port = port;
    host = "127.0.0.1";

    mediaLocation = "/persist${immichPath}";

    database = {
      enable = true;

      createDB = true;
      user = "immich";
      name = "immich";
      host = "/run/postgresql";
    };

    redis = {
      enable = true;

      host = "127.0.0.1";
      port = redisPort;
    };

    settings = {
      server.externalDomain = "https://${domain}";
      backup.database.enabled = true;
    };

  };

  # Postgres
  services.postgresql = {
    ensureDatabases = [ "immich" ];
    ensureUsers = [
      {
        name = "immich";
        ensureDBOwnership = true;
      }
    ];
  };

  # Redis
  services.redis.servers.immich = {
    enable = true;
    port = redisPort;
    bind = "127.0.0.1";
  };

  # Shouldn't be necessary anymore since it's under /persist/data
  environment.persistence."/persist".directories = [
    {
      directory = immichPath;
      user = "immich";
      group = "immich";
    }
  ];

  # Fail2Ban Jail
   services.fail2ban.jails.immich.settings = {
    filter = "immich";
    backend = "systemd";
    findtime = 86400;
    bantime  = 43200;
    maxretry = 5;
    chain = "FORWARD";
  };

  environment.etc."fail2ban/filter.d/immich.local".text = pkgs.lib.mkDefault( pkgs.lib.mkAfter ''
    [Definition]
    failregex = immich-server.*Failed login attempt for user.+from ip address\s?<ADDR>
    journalmatch = CONTAINER_TAG=immich-server
  '');

  # Nginx
  # Public: share links only; the apps use the internal domain.
  services.nginx.virtualHosts.${domain} = {
    serverName = domain;

    enableACME = false;
    useACMEHost = fqdn;
    forceSSL = true;

    # Share pages only read, plus POST for password unlock, downloads and "allow upload" shares.
    extraConfig = ''
      allow all;
      if ($request_method !~ ^(GET|HEAD|POST)$) { return 405; }
    '';

    locations = {
      "/".return = "404";

      "/share/" = proxyLocation "5m";
      "/s/" = proxyLocation "5m";
      "/_app/" = proxyLocation "5m";
      # favicons, custom.css, manifest.json, timeline skeletons
      "~ ^/[\\w.-]+\\.(ico|png|css|json)$" = proxyLocation "5m";

      # Upstream's shared-link routes (server/src/controllers/index.spec.ts) plus the public server/* the
      # web app loads. No {n} quantifiers: nixpkgs' config formatter splits them into blocks.
      "~ ^/api/(shared-links/(me|login)|albums/[0-9a-f-]+(/map-markers)?|assets(/[0-9a-f-]+(/(original|thumbnail|video/playback|video/stream/.+))?)?|timeline/buckets?|download/(info|archive)|search/metadata|server/(config|features|media-types|version|ping))$" = proxyLocation "100m";
    };
  };

  services.nginx.virtualHosts.${internalDomain} = {
    serverName = internalDomain;

    enableACME = false;
    useACMEHost = internalFqdn;
    forceSSL = true;

    locations."/" = proxyLocation "100000m";
  };

  services.borgbackup.jobs."immich" = {
    # immich media lives on the rpool/safe/persist/data dataset (mounted at /persist/data),
    # so snapshot that dataset directly. immichPath is "/data/immich", i.e. "immich" within it.
    paths = [ "${mountPoint}/immich" ];

    repo = env.cloudSettings.services.immich.borg-repository;
    preHook = ''
      ${pkgs.zfs}/bin/zfs destroy rpool/safe/persist/data@immich || true
      ${pkgs.zfs}/bin/zfs snapshot rpool/safe/persist/data@immich
      ${pkgs.coreutils}/bin/mkdir -p ${mountPoint}

      # Same as ./backup.nix
      ${pkgs.zfs}/bin/mount.zfs -o ro rpool/safe/persist/data@immich ${mountPoint}
    '';
    postHook = ''
      /run/wrappers/bin/umount ${mountPoint} || /run/wrappers/bin/umount -l ${mountPoint} || true
      ${pkgs.zfs}/bin/zfs destroy rpool/safe/persist/data@immich || true
    '';
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat /run/agenix/immich-backup_passphrase";
    };

    environment.BORG_RSH = "ssh -i ${env.userSettings.bach.ssh.root.location} -o IdentitiesOnly=yes";
    environment.BORG_CACHE_DIR = "/var/cache/borg";
    compression = "auto,lzma";
    startAt = "*-*-* 02:00:00";

    user = "root";
    group = "root";
  };

  # The module's ProtectSystem=strict only lets borg write ~/.cache/borg; 0700 because the files cache lists every backed-up path.
  systemd.services.borgbackup-job-immich.serviceConfig = {
    CacheDirectory = "borg";
    CacheDirectoryMode = "0700";
  };

  # Agenix
  age.secrets = {
    immich-backup_passphrase = {
      file = ../../secrets/immich-backup_passphrase.age;
    };
  };

  users.users.immich.uid = 15015;
  users.groups.immich.gid = 15015;

  users.users.redis-immich.uid = 995;
  users.groups.redis-immich.gid = 995;
}
  ;
}
