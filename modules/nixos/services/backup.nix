{ ... }:
{
  flake.nixosModules.backup =
{ pkgs, env, ... }:
let
  mountDirectory = "/var/tmp/borgjobs";
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

    # recursive so the child dataset rpool/safe/persist/data (Nextcloud, Immich,
    # static-files) is snapshotted too — it is NOT covered otherwise.
    datasets."rpool/safe/persist" = {
      useTemplate = [ "backup" ];
      recursive = true;
    };
  };

  services.borgbackup.jobs."generic" = {
    paths = [
      "${mountDirectory}/home"
      "${mountDirectory}/data/nextcloud"
      "${mountDirectory}/data/static-files"
      "${mountDirectory}/etc/machine-id"
      "${mountDirectory}/var/log"
      "${mountDirectory}/var/lib/acme"
      "${mountDirectory}/var/lib/calibre-web"
      "${mountDirectory}/var/lib/postgresql"
      "${mountDirectory}/var/lib/tailscale"
      "${mountDirectory}/etc/ssh"
      "${mountDirectory}/home/.ssh"
    ];
    repo = env.userSettings.bach.borg-repository;
    # /persist and /persist/data are separate ZFS datasets, so snapshot recursively and
    # bind-mount both the parent snapshot and the data child snapshot into place.

    preHook = ''
      ${pkgs.zfs}/bin/zfs destroy -r rpool/safe/persist@generic || true
      ${pkgs.zfs}/bin/zfs snapshot -r rpool/safe/persist@generic

      ${pkgs.coreutils}/bin/mkdir -p ${mountDirectory}
      ${pkgs.coreutils}/bin/mkdir -p ${mountDirectory}/data

      ${pkgs.coreutils}/bin/ls /persist/.zfs/snapshot/generic/ > /dev/null

      # ZFS only mounts a snapshot under .zfs/snapshot/<name> on first access (automount). Touch the path first so the automount happens synchronously, otherwise the bind below can capture the empty trigger directory (races on a cold cache after a reboot) and borg fails
      /run/wrappers/bin/mount --rbind /persist/.zfs/snapshot/generic ${mountDirectory}
      /run/wrappers/bin/mount --rbind /persist/data/.zfs/snapshot/generic ${mountDirectory}/data
    '';
    postHook = ''
      /run/wrappers/bin/umount -R ${mountDirectory}/data || /run/wrappers/bin/umount -l ${mountDirectory}/data || true
      /run/wrappers/bin/umount -R ${mountDirectory} || /run/wrappers/bin/umount -l ${mountDirectory} || true
      ${pkgs.zfs}/bin/zfs destroy -r rpool/safe/persist@generic || true
    '';
    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat /run/agenix/backup_passphrase";
    };

    environment.BORG_RSH = "ssh -i ${env.userSettings.bach.ssh.root.location} -o IdentitiesOnly=yes";
    compression = "auto,lzma";
    startAt = "*-*-* 01:00:00";

    user = "root";
    group = "root";
  };

  # Adds personal repo to Known Hosts. Otherwise impermanence erases it
  services.openssh.knownHosts."*.repo.borgbase.com" = {
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
