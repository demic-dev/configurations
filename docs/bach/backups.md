# Backups

bach's durable data is protected twice: local ZFS snapshots for recent mistakes, and encrypted offsite copies for disasters. This page covers both and how to restore from them.

## Snapshots

[sanoid] snapshots `rpool/safe/persist` and its children every hour, keeping 36 hourly, 30 daily and 3 monthly snapshots (`modules/services/backup.nix`). They're on the same pool, so they're instant and free, and gone if the pool is.

`recursive = true` matters: `rpool/safe/persist/data`, which holds Nextcloud, Immich and the static files, is a separate dataset and wouldn't be covered otherwise.

## Offsite copies

[borgbackup] sends encrypted copies to BorgBase, in two jobs with separate repositories:

| Job | Unit | Starts | Contents |
|---|---|---|---|
| `generic` | `borgbackup-job-generic` | 01:00 | `/home`, Nextcloud's data, static files, Postgres, ACME, calibre-web, Tailscale, logs, the machine-id and the ssh host key |
| `immich` | `borgbackup-job-immich` | 02:00 | the Immich library, including Immich's own database dumps |

Each job takes its own ZFS snapshot (`@generic`, `@immich`), mounts it read-only, backs up from it and destroys it, so every archive is crash-consistent. These snapshots are separate from sanoid's, which only prunes its own.

Nextcloud's database also gets a plain SQL dump every day at 03:15 into `/home/.backups/postgres/nextcloud` (`modules/services/nextcloud.nix`), which the next night's `generic` job picks up.

Not backed up: the Nix store and the OS, which are rebuilt from the flake, and `/var/cache`, whose contents rebuild on their own. OnlyOffice's and RabbitMQ's state (`/var/lib/onlyoffice`, `/var/lib/rabbitmq`) is persisted and snapshotted, but not in either borg job.

The jobs authenticate to BorgBase with bach's ssh host key and keep their cache in `/var/cache/borg`.

## What an archive contains

Plain files, not a ZFS dataset. The snapshot is only a consistent place to read from. `borg extract` gives regular files and needs no ZFS.

Because each job reads through a mount, stored paths have a three-component prefix: `var/tmp/borgjobs/…` for `generic`, `var/tmp/immich-borgbase/…` for `immich`. Strip it with `--strip-components 3`.

## Access a repository

Three things are needed: the repository URL (`env.userSettings.bach.borg-repository` and `env.cloudSettings.services.immich.borg-repository`, both in `secrets/sensitive/`), the passphrase (agenix `backup_passphrase` and `immich-backup_passphrase`), and bach's ssh host key. With those, any machine can read the backups, even with bach gone:

```sh
export BORG_REPO='ssh://…@….repo.borgbase.com/./repo'
export BORG_RSH='ssh -i /path/to/bach_host_key -o IdentitiesOnly=yes'
export BORG_PASSPHRASE='…'
borg list
```

Archives are named `bach-generic-…` and `bach-immich-…`.

## Restore a few files

To browse the newest archive and copy files out:

```sh
borg mount "::$(borg list --last 1 --short)" /mnt/restore
cp /mnt/restore/var/tmp/borgjobs/home/michele/Documents/foo.pdf ~/
borg umount /mnt/restore
```

Or extract one path directly, without the prefix:

```sh
borg extract --strip-components 3 "::$(borg list --last 1 --short)" \
  var/tmp/borgjobs/home/michele/Documents
```

## Roll back recent changes

If the pool is fine and the problem is recent, use a snapshot. It's instant and downloads nothing:

```sh
zfs list -t snapshot rpool/safe/persist
zfs rollback -r rpool/safe/persist@autosnap_2026-07-06_00:00:01_daily
```

`zfs rollback` refuses to go past newer snapshots unless given `-r`, which destroys every snapshot newer than the target. It doesn't touch `rpool/safe/persist/data`, which has its own snapshots. To pick out files instead, browse `/persist/.zfs/snapshot/<name>/`.

## Restore everything from borg

For a lost pool, or a point older than the snapshots go. The `generic` archive mirrors `/persist`, and the `immich` archive mirrors `/persist/data`, so extracting with the prefix stripped puts every path back where it belongs. Stop the services that own the data first:

```sh
systemctl stop postgresql immich-server immich-machine-learning phpfpm-nextcloud
borg extract --strip-components 3 -C /persist "::bach-generic-YYYY-MM-DDThh:mm:ss"
borg extract --strip-components 3 -C /persist/data "::bach-immich-YYYY-MM-DDThh:mm:ss"
```

Then reboot, so impermanence binds everything into place, or restart the services.

For a rebuild from nothing, follow [Disaster recovery](../RECOVERY.md).

[sanoid]: https://github.com/jimsalterjrs/sanoid
[borgbackup]: https://www.borgbackup.org/
