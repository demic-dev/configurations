# Memory on bach

bach has 8 GB of RAM and runs Immich, Nextcloud with OnlyOffice, Miniflux, calibre-web, and the Nix builds for both hosts. This page covers the settings that keep all of that from running out of memory.

## Root filesystem

The root is a tmpfs, so every file written outside a ZFS dataset lives in RAM until the next boot. Two places that only grow are ZFS datasets instead:

| Dataset | Mounted at | At boot |
|---|---|---|
| `rpool/local/tmp` | `/tmp` | emptied (`boot.tmp.cleanOnBoot`) |
| `rpool/local/cache` | `/var/cache` | kept |

Both sit under `rpool/local`, which sanoid doesn't snapshot and borg doesn't back up. The convention: `local` holds what can be rebuilt, `safe` holds what can't. Immich's ML models (about 1.4 GB) and borg's cache (`BORG_CACHE_DIR=/var/cache/borg`) live in `/var/cache`, so they survive reboots without ending up in backups.

The mounts in `modules/hosts/bach/hardware.nix` use `nofail`, so bach still boots if a dataset is missing, plus `x-systemd.before=local-fs.target`. `nofail` drops the ordering before `local-fs.target`, and without it a service could start writing into the tmpfs underneath before the dataset is mounted.

<details>
<summary>Why not persist each cache directory?</summary>

A line per cache under `environment.persistence."/persist"` works, but every new service that caches something needs its own line, and the caches end up in sanoid's snapshots of `rpool/safe/persist`. One dataset per mount point covers current and future caches.

</details>

## ZFS ARC

ZFS doesn't use the Linux page cache. It has its own read cache, the ARC. The ARC gives memory back under pressure, but in steps, slower than the page cache does. A fast allocation spike, like Immich loading a model, can reach the OOM killer before the ARC has made room. Uncapped, its ceiling on bach is 7.2 GB, nearly all of RAM.

The ARC is capped at 1 GiB with a kernel parameter in `modules/hosts/bach/hardware.nix`:

```nix
boot.kernelParams = [ "zfs.zfs_arc_max=1073741824" ];
```

`free` counts the ARC as used memory, not as cache. To see its real size and ceiling:

```sh
grep -E '^(size|c_max) ' /proc/spl/kstat/zfs/arcstats
```

## Swap

Swap is zram: a compressed block device in RAM (`zramSwap.enable` in `modules/hosts/bach/hardware.nix`). There is no swap on disk.

<details>
<summary>Why not swap on disk?</summary>

To write a page to a zvol, ZFS has to allocate memory for compression, checksums and the write queue, at the moment there is none left. Under pressure this can stall or deadlock the machine instead of slowing it down, and the OpenZFS docs advise against it. bach used a swap zvol until it froze for close to three hours.

The other disk options don't fit either: ZFS doesn't support swapfiles, and a partition means repartitioning the VPS disk.

</details>

## Nix builds

bach builds for both hosts. The nix-daemon runs with batch CPU scheduling and idle IO priority, and its cgroup is capped in `modules/hosts/bach/default.nix`:

```nix
systemd.services.nix-daemon.serviceConfig = {
  MemoryMax = "3G";
  MemorySwapMax = "512M";
};
```

`MemorySwapMax` matters because zram is RAM too: without it, a build that hits `MemoryMax` keeps growing into swap.

A build that needs more than 3 GiB fails inside the cgroup instead of pushing services out of memory. spotifast's test phase (now skipped) was OOM-killed on bach, and calibre's duckdb dependency fails to build on bach. Build those on satie: run `update` there instead of `update -b bach`.

## Core dumps

Core dumps aren't stored (`systemd.coredump.settings.Coredump.Storage = "none"` in `modules/hosts/bach/default.nix`). The default location, `/var/lib/systemd/coredump`, is on the tmpfs root, so a crash loop would fill RAM.
