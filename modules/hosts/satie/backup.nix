{ ... }:
{
  flake.nixosModules.satie-backup =
    { config, pkgs, env, ... }:
    {
      services.borgbackup.jobs.home = {
        paths = [
          "/home/michele"
          "/etc/ssh"
          "/etc/machine-id"
          "/var/lib/iwd"
          "/var/lib/bluetooth"
          "/var/lib/tailscale"
        ];
        # ~/Nextcloud is backed up on bach, ~/repos lives in git remotes.
        exclude = [
          "/home/michele/.cache"
          "/home/michele/Nextcloud"
          "/home/michele/repos"
        ];
        repo = env.userSettings.satie.borg-repository;
        encryption = {
          mode = "repokey-blake2";
          passCommand = "cat ${config.age.secrets.satie_backup_passphrase.path}";
        };
        environment.BORG_RSH = "ssh -i ${env.userSettings.satie.ssh.root.location} -o IdentitiesOnly=yes";
        # lzma, as on bach, costs a laptop battery and fan.
        compression = "auto,zstd";
        startAt = "daily";
        # satie is often asleep at the scheduled time: run on wake instead of skipping the day.
        persistentTimer = true;
        # Holds off idle suspend only. Closing the lid still suspends (LidSwitchIgnoreInhibited=yes,
        # logind.conf(5)); the module's --checkpoint-interval 600 lets the next run resume.
        inhibitsSleep = true;
        prune.keep = {
          daily = 7;
          weekly = 4;
          monthly = 6;
        };
        # A failed ping must not mark a good backup as failed; the missing ping already reports it.
        postCreate = ''
          ${pkgs.curl}/bin/curl -fsS -m 10 --retry 5 -o /dev/null "$(cat ${config.age.secrets.satie_healthchecks_ping_url.path})" || true
        '';
      };

      age.secrets = {
        satie_backup_passphrase.file = ../../../secrets/satie_backup_passphrase.age;
        satie_healthchecks_ping_url.file = ../../../secrets/satie_healthchecks_ping_url.age;
      };
    };
}
