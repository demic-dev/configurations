{ ... }:
{
  flake.nixosModules.backup =
{ pkgs, env, ... }:
let
  mountDirectory = "/var/tmp/borgjobs/";
in
{
  services.sanoid = {
    enable = true;
    templates.backup = {
      hourly = 36;
      daily = 30;
      monthly = 3;
      autoprune = true;
      autosnap = true;
    };

    datasets."rpool/safe/persist" = {
      useTemplate = [ "backup" ];
    };
  };

  services.borgbackup.jobs."borgbase" = {
    paths = [
      "/home"
      "/data"
      "/etc/machine-id"
      "/var/log"
      "/var/lib/acme"
      "/var/lib/calibre-web"
      "/var/lib/postgresql"
      "/var/lib/tailscale"
    ];
    exclude = [
      # Until the single-backup-per-service is not ready, I exclude immich declaratively
      "/data/immich"
    ];
    repo = env.userSettings.bach.borg-repository;
    preHook = ''
      ${pkgs.zfs}/bin/zfs destroy rpool/safe/persist@borgbase && true
      ${pkgs.zfs}/bin/zfs snapshot rpool/safe/persist@borgbase
      /run/wrappers/bin/mount --bind /persist/.zfs/snapshot/borgbase ${mountDirectory} 
    '';
    postHook = ''
      /run/wrappers/bin/umount ${mountDirectory}
      ${pkgs.zfs}/bin/zfs destroy rpool/safe/persist@borgbase
    '';
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat /run/agenix/backup_passphrase";
    };
    environment.BORG_RSH = "ssh -i /home/michele/.ssh/id_ed25519";
    compression = "auto,lzma";
    startAt = "daily";

    user = "root";
    group = "root";
  };

  environment.persistence."/persist".directories = [ mountDirectory ];

  # Adds personal repo to Known Hosts. Otherwise impermanence erases it
  programs.ssh.knownHosts."*.repo.borgbase.com" = {
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMS3185JdDy7ffnr0nLWqVy8FaAQeVh1QYUSiNpW5ESq";
  };

  # Agenix
  age.secrets = {
    backup_passphrase = {
      file = ../../../secrets/backup_passphrase.age;
    };
  };
}
  ;
}
