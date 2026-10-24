# ❄ Nix Config

One **dendritic** flake for all my machines:

- **`bach`** — aarch64-linux VPS. Self-hosted services (Nextcloud + OnlyOffice, Immich,
  Miniflux, Calibre-Web, a Hugo site, static files; Ghost is configured but off). Encrypted ZFS
  unlocked over SSH in the initrd, tmpfs root with impermanence. Public on 80/443 only; everything
  else, SSH included (Tailscale SSH), goes through the tailnet.
- **`satie`** — aarch64-linux Apple-Silicon (Asahi) laptop. niri + noctalia desktop.

## The dendritic pattern

The flake is built with [flake-parts] + [import-tree]. **Every `.nix` file under `./modules`
is auto-imported** as a flake-parts module, so there is no list of imports to maintain. Other files
(`config.kdl`, firmware, CA certificates) are ignored and sit next to the module that uses them.

A file under `modules/` does one of two things:

1. **Registers an aspect**: a self-contained piece of config, one file per *thing*. When a
   feature has a system half and a home half, both live in the same file:
   ```nix
   # modules/desktop/niri/default.nix
   { config, ... }: {
     flake.nixosModules.niri = { programs.niri.enable = true; };
     flake.homeModules.niri = { pkgs, ... }: { xdg.configFile."niri/config.kdl".source = ./config.kdl; };
   }
   ```
   **Registering does nothing on its own.**
2. **Assembles a host**: `modules/hosts/<host>/default.nix` lists the aspects that machine runs.
   The import is the switch; there are no `enable` flags.

### Layout

```
flake.nix            flake-parts entry: home-manager flakeModule + import-tree ./modules
env.nix              shared settings, passed to every module as `env`
modules/
  hosts/<host>/      default.nix: nixosConfigurations.<host>, its aspect list, host basics
                     hardware.nix (+ zfs.nix on bach) → <host>-hardware
                     network.nix, users.nix (+ persistence.nix, eduroam.nix) → the <host> aspect
  base/              core, michele, ssh, tailscale, impermanence
  desktop/           desktop, niri, noctalia, gtk, xdg, zen, ghostty, screenshot, pcmanfm
  dev/               git, fish, nvim, claude
  services/          nginx, acme, backup, nextcloud, immich, miniflux, …, tailnet-server
secrets/             agenix + git-agecrypt (see secrets/README.md)
docs/RECOVERY.md     disaster recovery
```

### Recipes

- **Add a service or app**: a new file in the right folder registering
  `flake.nixosModules.<x>` and/or `flake.homeModules.<x>`, then add `<x>` to the host's NixOS list
  (`hosts/<host>/default.nix`) or home list (`hosts/<host>/users.nix`).
- **Toggle one**: comment or uncomment its name in that list.
- **Add a host**: a new `modules/hosts/<host>/` folder.
- **Persistence** lines stay with the service they belong to (`environment.persistence."/persist"`).
  A host without `/persist` imports `impermanence` and sets `environment.persistence."/persist".enable = false`,
  which makes those lines inert (that's satie).

> **`env.nix` note:** shared values (`env.cloudSettings`, `env.userSettings`) are threaded
> through modules via `specialArgs`/`extraSpecialArgs` rather than flake-parts options. This
> is a deliberate, pragmatic exception to strict dendritic purity that keeps every module
> body plain NixOS/home-manager config.

## Build and deploy

`update` is a fish function on every host:

```bash
update                          # build here, switch this host
update -b bach                  # build on bach, switch this host
update -b bach -d bach          # build on bach, switch bach
update -d bach -m boot          # build here, make it bach's next boot
update -b bach -m test --show-trace   # any other flag goes to nixos-rebuild
unlock-bach                     # type the ZFS passphrase into bach's initrd after a reboot
nix flake check                 # evaluate both configurations
```

Evaluate on satie: git-agecrypt only decrypts `secrets/sensitive/` in that checkout, so a
configuration evaluated anywhere else gets ciphertext for bach's IP, domains and email. agenix
secrets (`secrets/*.age`) decrypt at activation, never at evaluation.

Builds on bach run in nix-daemon's cgroup, capped at 3 GB RAM + 512 MB swap so they can't push the
services out. Packages that compile from source and need more (spotifast, calibre's Python chain)
are better built on satie.

## Backups & restore

`bach` has two layers of protection for `rpool/safe/persist` (everything durable lives there —
impermanence wipes the rest on boot):

- **[sanoid]** — automatic **local** ZFS snapshots on a schedule (hourly/daily/monthly, autopruned).
  Fast, on-host, free. Your first line of defence for "undo the last few hours/days".
- **[borgbackup]** — encrypted **offsite** copies at BorgBase, in two jobs:
  - `generic` (`borgbackup-job-generic.service`, ~01:00) → `/home`, Nextcloud, static files,
    Postgres, ACME, Calibre, Tailscale, logs, machine-id, the ssh host keys (and Ghost's data while
    Ghost is enabled).
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
