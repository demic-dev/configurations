# Health checks

bach mails an alert when something on it breaks. This page covers what is checked, how the mail goes out, and how to test it. The alerts are in `modules/services/health.nix`.

## Mail

Alerts go out through msmtp, set as the system `sendmail`, to Proton's SMTP server. They are sent from and to `homelab@` the domain in `env.cloudSettings.fqdn`. msmtp reads the SMTP token from the agenix secret `homelab_smtp_token` through `passwordeval`, so the token stays out of the Nix store.

`passwordeval` runs as whoever calls `sendmail`: the wrapper in `/run/wrappers/bin` isn't setuid. The secret is owned by `nextcloud` with mode 0400, so root and Nextcloud can read it and other users can't.

### Mail from Nextcloud and Immich

Nextcloud and Immich send their own mail (password resets, share and album notifications, Immich's welcome mail) from the same `homelab@` address with the same token.

- Nextcloud pipes to the same msmtp `sendmail`, as the `nextcloud` user (`modules/services/nextcloud.nix`). `mail_from_address` and `mail_domain` make the sender `homelab@`, the only one Proton accepts. Nextcloud looks for `sendmail` in its `PATH`, so `nextcloud-cron` gets `/run/wrappers/bin` added for the mail its background jobs send.
- Immich talks SMTP to Proton itself, through `notifications.smtp` in `services.immich.settings` (`modules/services/immich.nix`). The password is a `_secret` entry: the module loads the file with `LoadCredential=` and writes it into `/run/immich/config.json` when the unit starts. While that file is in use, the admin page can't change any setting.

## Checks

| What breaks | What notices | When |
|---|---|---|
| Any system service fails, including borg and the scrub | systemd, through `OnFailure=` | when the unit fails |
| A ZFS pool degrades, a disk reports errors | ZED | on the ZFS event |
| bach is down or frozen, or the backup didn't run | healthchecks.io | when a ping is missing |
| A ZFS pool is 80 % full or more | `zpool-capacity` | daily |
| Memory pressure stays high | `memory-pressure` | every 5 minutes |
| The borg repository is damaged | `borg-check` | 3rd of each month, 04:00 |

The three timer jobs only exit non-zero. The mail comes from the `OnFailure=` drop-in, like any other failed service.

### Failed services

A drop-in in `/etc/systemd/system/service.d/` adds `OnFailure=notify-mail@%n.service` to every system service. systemd has this top-level drop-in folder, but NixOS has no option for it, so the file comes from a package in `systemd.packages`. When a unit fails, `notify-mail@<unit>.service` mails its name and the last 50 lines of `systemctl status`.

A service with `Restart=` only fails once systemd gives up restarting it, so a crash loop sends one mail. A timer job that fails on every run would send one per run, so the mail unit sends at most one mail per unit per day. It keeps a stamp per unit in `/run/notify-mail/`, which a reboot clears.

The mail unit itself has an empty `OnFailure=`, so a failing mail doesn't start a mail about itself.

### ZFS events

ZED, the ZFS Event Daemon, runs scripts for the kernel's ZFS events (a disk erroring, a pool degrading, a scrub finishing) and one of them sends mail. It mails the same address through the same `sendmail`, at most once an hour for similar events (`ZED_NOTIFY_INTERVAL_SECS = 3600`). With `ZED_NOTIFY_VERBOSE` off, a scrub that finishes on a healthy pool sends no mail.

### healthchecks.io

After each successful `borg create` of the `generic` job, bach requests the URL in the agenix secret `healthchecks_ping_url`. healthchecks.io mails when a ping doesn't arrive in time. That covers what bach can't report itself: being down or frozen. The expected period and grace time are set on healthchecks.io, not in the flake.

A failed ping doesn't fail the backup. The missing ping already reports it. The `immich` job doesn't ping.

### Pool capacity

ZFS slows down past about 80 % full. `zpool-capacity` runs daily and fails when any pool's capacity, from `zpool list`, is 80 % or more. `df` isn't used because it shows datasets, not the pool.

### Memory pressure

`memory-pressure` runs every 5 minutes and fails when the `avg300` value on the `some` line of `/proc/pressure/memory` is 10 or more. That value is the percentage of the last 5 minutes in which at least one task waited for memory. The check exists because swap thrashing froze bach on 21 October 2026 without any unit failing.

The 10 % threshold is a starting guess. To see bach's normal values:

```sh
cat /proc/pressure/memory
```

### Borg repository

`borg-check` runs `borg check` on the `generic` repository on BorgBase on the 3rd of each month at 04:00, away from the backup (01:00) and the scrub (1st and 15th, 02:30). The `immich` repository isn't checked.

## What isn't checked

- satie. It is often off, so a missing ping would be a false alarm.
- Disk hardware (SMART). bach is a VPS and its disks are the provider's. ZFS checksums and the scrub still catch corrupted data, and ZED reports it.
- BorgBase quota and repeated backup failures. BorgBase mails about those itself.

## Test the alert mail

Start a mail unit for a made-up unit:

```sh
sudo systemctl start notify-mail@test.service
```

A mail with the subject `bach: test failed` arrives. Its body is empty, because `test.service` doesn't exist. A second run within a day sends nothing. To send again, remove the stamp:

```sh
sudo rm /run/notify-mail/test
```

If no mail arrives, the msmtp error is in the unit's journal:

```sh
journalctl -u notify-mail@test.service
```
