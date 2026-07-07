{ ... }:
{
  flake.nixosModules.immich =
{ pkgs, env, ... }:
let
  fqdn = env.cloudSettings.fqdn;
  domain = "${env.cloudSettings.services.immich.subdomain}.${env.cloudSettings.fqdn}";
  port = env.cloudSettings.services.immich.port;
  redisPort = port + 1;

  mountPoint = "/var/tmp/immich-borgbase";

  immichPath = "/data/immich";
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
        proxy_set_header Host $host; 
        proxy_set_header X-Forwarded-Proto $scheme; 
        proxy_set_header X-Real-IP $remote_addr; 
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_max_temp_file_size 16384m; 

        client_max_body_size 100m;
      '';
    };
  };

  services.nginx.virtualHosts."bach.tailcd20d8.ts.net" = {
    serverName = "bach.tailcd20d8.ts.net";

    enableACME = false;
    useACMEHost = fqdn;
    forceSSL = true;

    locations."/" = {
      recommendedProxySettings = true;
      proxyPass = "http://localhost:${toString port}";
      proxyWebsockets = true;
      extraConfig = ''
        proxy_set_header Host $host; 
        proxy_set_header X-Forwarded-Proto $scheme; 
        proxy_set_header X-Real-IP $remote_addr; 
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_max_temp_file_size 16384m; 

        client_max_body_size 100000m;
      '';
    };
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
      /run/wrappers/bin/mount --bind /persist/data/.zfs/snapshot/immich ${mountPoint}
    '';
    postHook = ''
      /run/wrappers/bin/umount ${mountPoint} || true
      ${pkgs.zfs}/bin/zfs destroy rpool/safe/persist/data@immich || true
    '';
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat /run/agenix/immich-backup_passphrase";
    };

    environment.BORG_RSH = "ssh -i ${env.userSettings.bach.ssh.root.location} -o IdentitiesOnly=yes";
    compression = "auto,lzma";
    startAt = "*-*-* 02:00:00";

    user = "root";
    group = "root";
  };

  # Agenix
  age.secrets = {
    immich-backup_passphrase = {
      file = ../../../secrets/immich-backup_passphrase.age;
    };
  };

  users.users.immich.uid = 15015;
  users.groups.immich.gid = 15015;

  users.users.redis-immich.uid = 995;
  users.groups.redis-immich.gid = 995;
}
  ;
}
