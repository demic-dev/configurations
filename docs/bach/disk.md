# Disk and boot on bach

bach runs on an encrypted ZFS pool with a root filesystem that's wiped at every boot. This page covers the datasets, what survives a reboot, and how the pool gets unlocked.

## Datasets

The pool is `rpool`, encrypted with ZFS native encryption. Datasets are split by whether their contents can be rebuilt:

| Dataset | Mounted at | Contents |
|---|---|---|
| `rpool/local/nix` | `/nix` | the Nix store |
| `rpool/local/tmp` | `/tmp` | temporary files, including nginx's upload buffers; emptied at boot |
| `rpool/local/cache` | `/var/cache` | caches (Immich's models, borg) |
| `rpool/safe/persist` | `/persist` | everything that must survive |
| `rpool/safe/persist/data` | `/persist/data` | Nextcloud, Immich media, static files |

`local` holds what can be rebuilt, `safe` holds what can't. Only `safe` gets snapshots and backups (see [Backups](backups.md)).

Mounts are declared in `modules/hosts/bach/hardware.nix`. A scrub runs on the 1st and 15th of each month at 02:30 (`modules/hosts/bach/zfs.nix`).

## Impermanence

`/` is a tmpfs. Anything not on a dataset is gone after a reboot, and lives in RAM until then. What should stay is listed under `environment.persistence."/persist"`, and the [impermanence] module bind-mounts it from `/persist` into place at boot.

bach's own list (`modules/hosts/bach/persistence.nix`) is short: `/etc/machine-id`, the ssh host key, `/var/log` and `/home`. Each service persists its own directories in its own file.

The impermanence aspect (`modules/base/impermanence.nix`) is imported on every host, with `hideMounts` on so the bind mounts don't clutter file managers. satie has no `/persist`, so it sets `environment.persistence."/persist".enable = false`, and the persistence lines in shared aspects do nothing there.

## Unlocking at boot

The initrd runs systemd and an ssh server on port 2222 (`modules/hosts/bach/zfs.nix`). It accepts satie's michele key, and has a host key of its own at `/persist/etc/secrets/initrd/ssh_host_ed25519_key`, separate from the system's. To unlock after a reboot, from satie:

```sh
unlock-bach
```

The ssh session goes straight to the pending "Enter key for rpool" prompt, because root's shell in the initrd is `systemd-tty-ask-password-agent`. After the passphrase, the session closes and boot continues.

If the prompt never appears, the pool import failed. Debug from the VPS provider's VNC console, where the initrd drops to an emergency shell.

The initrd gets its network config from `networking.interfaces` and `networking.defaultGateway` (`modules/hosts/bach/network.nix`). The gateway's `interface` has to be set: nixpkgs only copies the default route into the initrd when it is, and without the route port 2222 is unreachable from outside the subnet.

`boot.zfs.forceImportRoot` is on (`modules/hosts/bach/hardware.nix`). The risk it protects against, another machine importing the same pool, doesn't exist on a single VM. With it on, a hard reboot after a crash imports the pool on its own, instead of needing the VNC console.

[impermanence]: https://github.com/nix-community/impermanence
