# Backup

satie sends an encrypted copy of its data to BorgBase once a day. This page covers what's in it, how the timer copes with sleep, and how to restore.

## What's in an archive

The job `home` (`modules/hosts/satie/backup.nix`, unit `borgbackup-job-home`) backs up:

- `/home/michele`, without `~/.cache`, `~/Nextcloud` and `~/repos`
- `/etc/ssh` (satie's host key) and `/etc/machine-id`
- `/var/lib/iwd`, `/var/lib/bluetooth` and `/var/lib/tailscale`

Not backed up:

- `~/Nextcloud`: bach backs up Nextcloud's data (see [Backups](../bach/backups.md)).
- `~/repos`: the git remotes are the copy. Uncommitted changes and unpushed commits aren't backed up anywhere.
- `/home/agent`, the Nix store and the OS, which are rebuilt from the flake.

`~/notes` and `~/nixos` are symlinks. borg stores a symlink as a link and doesn't follow it.

ext4 has no snapshots, so borg reads live files. A file written during the run, such as an open browser database, can be saved in an inconsistent state.

Archives are named `satie-home-…`. Prune keeps 7 daily, 4 weekly and 6 monthly archives.

## Sleep

The timer runs daily with `Persistent=true`: if satie was asleep or off at the scheduled time, the job starts as soon as it wakes and the network is up.

During a run, idle suspend waits (`systemd-inhibit --what=sleep`). Closing the lid still suspends, because logind ignores inhibitors for the lid switch by default (`LidSwitchIgnoreInhibited=yes`, logind.conf(5)). borg writes a checkpoint every 10 minutes, so the next run reuses what was already uploaded.

## Monitoring

After each successful `borg create`, the job pings healthchecks.io. The check has a grace period of 3 days and mails when no ping arrives. satie sends no mail of its own: a failed run shows in the shell greeting's failed units.

## Access the repository

You need the repository URL (`env.userSettings.satie.borg-repository`, from `secrets/sensitive/satie-borgbase-repository.age`), the passphrase (agenix `satie_backup_passphrase`) and satie's ssh host key, which BorgBase authorises.

On satie, the module installs a wrapper with all three set:

```sh
sudo borg-job-home list
sudo borg-job-home info
```

From another machine:

```sh
export BORG_REPO='ssh://…@….repo.borgbase.com/./repo'
export BORG_RSH='ssh -i /path/to/satie_host_key -o IdentitiesOnly=yes'
export BORG_PASSPHRASE='…'
borg list
```

## Restore a few files

```sh
cd /tmp
sudo borg-job-home extract ::<archive> home/michele/path/to/file
```

Paths are stored without the leading `/`. Run a backup by hand with `sudo systemctl start borgbackup-job-home`.
