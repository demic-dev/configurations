{ ... }:
{
  flake.nixosModules.health =
{ config, pkgs, env, ... }:
{
  programs.msmtp = {
    enable = true;
    setSendmail = true;
    accounts.default = {
      host = "smtp.protonmail.ch";
      port = 587;
      auth = true;
      tls = true;
      tls_starttls = true;
      from = "homelab@${env.cloudSettings.fqdn}";
      user = "homelab@${env.cloudSettings.fqdn}";
      passwordeval = "cat ${config.age.secrets.homelab_smtp_token.path}";
    };
  };

  # A top-level service.d/ drop-in applies to every service. NixOS has no option for one, but
  # generateUnits in nixos/lib/systemd-lib.nix links each subfolder of a package's
  # etc/systemd/system/ into the unit folder.
  systemd.packages = [
    (pkgs.writeTextDir "etc/systemd/system/service.d/notify-mail.conf" ''
      [Unit]
      OnFailure=notify-mail@%n.service
    '')
    # Without this, a failing mail unit would start another mail unit about itself. systemd
    # applies drop-ins in file-name order across folders, so a different name could sort
    # before notify-mail.conf and be overridden; the same name masks the service.d/ file
    # (systemd.unit(5), "Top level drop-ins with template units").
    (pkgs.writeTextDir "etc/systemd/system/notify-mail@.service.d/notify-mail.conf" ''
      [Unit]
      OnFailure=
    '')
  ];

  systemd.services."notify-mail@" = {
    description = "Mail that %i failed";
    scriptArgs = "%i";
    serviceConfig = {
      Type = "oneshot";
      RuntimeDirectory = "notify-mail";
      # Keeps the stamps between runs; they still go away on reboot.
      RuntimeDirectoryPreserve = true;
    };
    script = ''
      stamp="/run/notify-mail/$1"
      # At most one mail per unit per day, so a timer that fails every run doesn't flood the inbox.
      if [ -n "$(find "$stamp" -mmin -1440 2>/dev/null)" ]; then
        exit 0
      fi
      {
        printf 'To: %s\nSubject: bach: %s failed\n\n' 'homelab@${env.cloudSettings.fqdn}' "$1"
        systemctl status --no-pager --full --lines=50 "$1"
      } | /run/wrappers/bin/sendmail 'homelab@${env.cloudSettings.fqdn}'
      touch "$stamp"
    '';
  };

  # ZED adds its own Subject: header when ZED_EMAIL_OPTS has no @SUBJECT@ (zed-functions.sh, ZFS 2.4.4).
  services.zfs.zed.settings = {
    ZED_EMAIL_ADDR = [ "homelab@${env.cloudSettings.fqdn}" ];
    ZED_EMAIL_PROG = "/run/wrappers/bin/sendmail";
    ZED_EMAIL_OPTS = "@ADDRESS@";
    ZED_NOTIFY_INTERVAL_SECS = 3600;
    ZED_NOTIFY_VERBOSE = false;
  };

  # healthchecks.io mails when this ping stops arriving, which also covers bach being down.
  # A failed ping must not mark a good backup as failed; the missing ping already reports it.
  services.borgbackup.jobs.generic.postCreate = ''
    ${pkgs.curl}/bin/curl -fsS -m 10 --retry 5 -o /dev/null "$(cat ${config.age.secrets.healthchecks_ping_url.path})" || true
  '';

  # ZFS slows down past about 80 % full; df shows datasets, not the pool.
  systemd.services.zpool-capacity = {
    description = "Fail when a ZFS pool is over 80 % full";
    startAt = "daily";
    serviceConfig.Type = "oneshot";
    path = [ config.boot.zfs.package pkgs.gawk ];
    script = ''
      zpool list -H -p -o capacity | awk '$1 >= 80 { full = 1 } END { exit full }'
    '';
  };

  # Swap thrashing froze bach on 21 Oct 2026 without any unit failing.
  # avg300 is the share of the last 5 minutes some task waited on memory.
  # The 10 % threshold is a guess, to tune against bach's normal values.
  systemd.services.memory-pressure = {
    description = "Fail when memory pressure stays high";
    path = [ pkgs.gawk ];
    startAt = "*:0/5";
    serviceConfig.Type = "oneshot";
    script = ''
      awk '/^some/ { split($4, kv, "="); exit (kv[2] >= 10) }' /proc/pressure/memory
    '';
  };

  # Away from the backup (01:00) and the scrub (1st and 15th, 02:30).
  systemd.services.borg-check = {
    description = "Check the borg repository on BorgBase";
    startAt = "*-*-03 04:00:00";
    serviceConfig.Type = "oneshot";
    script = ''
      /run/current-system/sw/bin/borg-job-generic check
    '';
  };

  age.secrets = {
    homelab_smtp_token.file = ../../secrets/homelab_smtp_token.age;
    healthchecks_ping_url.file = ../../secrets/healthchecks_ping_url.age;
  };
}
  ;
}
