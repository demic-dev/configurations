# ❄ Nix Config

One **dendritic** flake for all my machines:

- **`bach`** — aarch64-linux VPS. ~12 self-hosted services (Nextcloud, Immich, Ghost,
  Miniflux, Calibre-Web, a Hugo site…), ZFS + impermanence with remote LUKS/ZFS unlock,
  agenix + git-agecrypt secrets.
- **`satie`** — aarch64-linux Apple-Silicon (Asahi) laptop. Hyprland + DankMaterialShell
  desktop, agenix secrets.

## The dendritic pattern

The flake is built with [flake-parts] + [import-tree]. **Every `.nix` file under `./modules`
is auto-imported** as a flake-parts module — there is no central list of imports to maintain.

A file under `modules/` does one of two things:

1. **Registers an aspect** — a reusable, self-contained piece of config:
   ```nix
   # modules/nixos/services/immich.nix
   { ... }: {
     flake.nixosModules.immich = { config, pkgs, env, ... }: {
       services.immich.enable = true;
       # …everything Immich needs: nginx vhost, postgres, redis, backup, fail2ban…
     };
   }
   ```
   NixOS aspects register under `flake.nixosModules.<name>`; home-manager aspects under
   `flake.homeModules.<name>`. **Registering an aspect does nothing on its own** — it just
   makes it available.

2. **Assembles a host** — `modules/hosts/<host>.nix` lists the aspects that machine runs.
   This is the single **toggle surface**:
   ```nix
   # modules/hosts/bach.nix (excerpt)
   modules = with config.flake.nixosModules; [
     bach-hardware core networking optimization users sudo
     ssh tailscale nginx acme postgresql fail2ban backup
     nextcloud immich calibre miniflux hugo ghost
   ];
   ```

### Recipes

- **Add a service / app** → create a file in `modules/nixos/services/` (or
  `modules/home/…`) that registers `flake.nixosModules.<x>` / `flake.homeModules.<x>`,
  then add `<x>` to the host's module list.
- **Add a host** → create `modules/hosts/<host>.nix` with a `flake.nixosConfigurations.<host>`
  that lists the aspects it wants.
- **Toggle a service on a host** → comment/uncomment its name in that host's module list.
  (No `enable` flags — the import *is* the switch.)

### Layout

```
flake.nix                     # flake-parts entry: home-manager flakeModule + import-tree ./modules
env.nix                       # shared settings hub, imported per host, passed via specialArgs
modules/
  hosts/{bach,satie}.nix     # per-machine assembly + toggle surface
  nixos/                      # flake.nixosModules.<x>
    core.nix networking.nix optimization.nix sudo.nix users.nix desktop.nix
    hardware/{bach,asahi}.nix
    services/*.nix
  home/                       # flake.homeModules.<x>
    git.nix  shells/*.nix  desktop/*.nix
disko/                        # bach ZFS + impermanence (imported by nixos/hardware/bach.nix)
secrets/                      # see secrets/README.md
```

> **`env.nix` note:** shared values (`env.cloudSettings`, `env.userSettings`) are threaded
> through modules via `specialArgs`/`extraSpecialArgs` rather than flake-parts options. This
> is a deliberate, pragmatic exception to strict dendritic purity that keeps every module
> body plain NixOS/home-manager config.

## Build / switch

```bash
nixos-rebuild switch --flake .#bach     # on bach
nixos-rebuild switch --flake .#satie   # on satie
nix flake check                         # evaluate both configurations
```

Secrets decrypt at activation, not evaluation. Note that `env.cloudSettings.*` reads
git-agecrypt files under `secrets/sensitive/`; a full local `nix eval` of `bach` only
produces real values where that smudge filter is active.

## Backups & restore

`bach` has two layers of protection for `rpool/safe/persist` (everything durable lives there —
impermanence wipes the rest on boot):

- **[sanoid]** — automatic **local** ZFS snapshots on a schedule (hourly/daily/monthly, autopruned).
  Fast, on-host, free. Your first line of defence for "undo the last few hours/days".
- **[borgbackup]** — encrypted **offsite** copies at BorgBase, in two jobs:
  - `generic` (`borgbackup-job-generic.service`, ~01:00) → `/home`, Nextcloud, static files,
    Postgres, ACME, Calibre, Ghost, Tailscale, logs, machine-id.
  - `immich` (`borgbackup-job-immich.service`, ~02:00) → the Immich media library.

Each borg job takes its **own** throwaway ZFS snapshot (`@generic` / `@immich`), bind-mounts it,
backs up from that frozen view, then destroys it — so archives are crash-consistent. These
transient snapshots are independent of sanoid's `autosnap_*` snapshots; sanoid only prunes its own,
so the two never interfere.

> **What borg stores:** plain files, **not** a ZFS snapshot or dataset. The snapshot is only a
> consistent *read source* at backup time. `borg extract` therefore gives you regular
> files/dirs — no ZFS needed to read a backup. Because each job reads through a bind-mount, stored
> paths carry a prefix (`var/tmp/borgjobs/…` for `generic`, `var/tmp/immich-borgbase/…` for
> `immich`) — both 3 path components, stripped with `--strip-components 3`.

### Prerequisites to read a repo

The repo URL (`env.userSettings.bach.borg-repository` / `env.cloudSettings.services.immich.borg-repository`),
the passphrase (agenix: `backup_passphrase` / `immich-backup_passphrase`), and the SSH key
(`/home/michele/.ssh/id_ed25519`). With those three you can restore from **any** machine, even if
`bach` is gone:

```bash
export BORG_REPO='ssh://…@…repo.borgbase.com/./repo'
export BORG_RSH='ssh -i ~/.ssh/id_ed25519'
export BORG_PASSPHRASE='…'
borg list                      # list archives (named bach-generic-… / bach-immich-…)
```

### Case A — no host access, "I just want some files"

Recover individual files onto a laptop; nothing to do with ZFS or the running system.

```bash
# Browse the newest archive like a folder, copy what you need, then unmount:
borg mount "::$(borg list --last 1 --short)" /mnt/restore
cp /mnt/restore/var/tmp/borgjobs/home/michele/Documents/foo.pdf ~/
borg umount /mnt/restore

# …or extract one path directly, dropping the mount prefix:
borg extract --strip-components 3 "::$(borg list --last 1 --short)" \
  var/tmp/borgjobs/home/michele/Documents
```

### Case B — I have the host, "restore everything as it was"

If the pool is intact and you only need to undo recent changes, prefer sanoid — it's instant and
needs no download:

```bash
zfs list -t snapshot rpool/safe/persist        # pick an autosnap_… point in time
zfs rollback rpool/safe/persist@autosnap_2026-07-06_00:00:01_daily
```

To restore from borg (pool lost / older than sanoid retention), extract **into `/persist`** — the
archives are a snapshot of `/persist`, so stripping the 3-component prefix lands paths exactly where
they belong (`var/tmp/borgjobs/home` → `/persist/home`, etc.). Stop the services that own the data
first so nothing is half-written:

```bash
systemctl stop postgresql immich-server immich-machine-learning nextcloud-setup
# generic: archive mirrors /persist (incl. the data child at data/…), so extract into /persist
borg extract --strip-components 3 -C /persist "::bach-generic-YYYY-MM-DDThh:mm:ss"
# immich: archive mirrors the data dataset (/persist/data), so extract into /persist/data
borg extract --strip-components 3 -C /persist/data "::bach-immich-YYYY-MM-DDThh:mm:ss"
# then reboot (impermanence re-binds /persist/* onto the live paths) or restart the services
```

Rule of thumb: **sanoid for recent, local rollbacks; borg for disaster recovery or pulling files
off-host.** They're complementary, not redundant.

## References

1. [Dendritic pattern](https://github.com/mightyiam/dendritic)
2. [https://github.com/carjorvaz/nixos](https://github.com/carjorvaz/nixos)
3. [https://github.com/diogotcorreia/dotfiles](https://github.com/diogotcorreia/dotfiles)
4. [https://github.com/librephoenix/nixos-config](https://github.com/librephoenix/nixos-config)
5. [https://github.com/Baitinq/nixos-config](https://github.com/Baitinq/nixos-config)

[flake-parts]: https://flake.parts
[import-tree]: https://github.com/vic/import-tree
[sanoid]: https://github.com/jimsalterjrs/sanoid
[borgbackup]: https://www.borgbackup.org/
