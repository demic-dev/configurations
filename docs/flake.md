# How the flake is wired

The flake follows the dendritic pattern: every file under `modules/` is a flake-parts module, and hosts are assembled from named pieces of config called aspects.

## Entry point

`flake.nix` uses [flake-parts] and imports two things: home-manager's flake module, which provides `flake.homeModules`, and every `.nix` file under `modules/`, collected by [import-tree]. There is no import list to maintain. Files that aren't `.nix` (`config.kdl`, certificates, firmware) are ignored by import-tree and sit next to the module that uses them.

## Aspects

A file under `modules/` registers one or both halves of an aspect:

```nix
{ config, ... }:
{
  flake.nixosModules.niri = { programs.niri.enable = true; };
  flake.homeModules.niri = { pkgs, ... }: { xdg.configFile."niri/config.kdl".source = ./config.kdl; };
}
```

Registering does nothing on its own. An aspect only takes effect when a host imports it.

One file covers one thing, including every layer it touches. `modules/services/immich.nix` holds the Immich service, its nginx vhosts, its database and Redis, its borg job, its secrets and its persistence lines. To understand a service, read one file.

`flake.nixosModules` is declared as `lazyAttrsOf deferredModule`, so several files can define the same aspect and the definitions merge. The host aspects use this: `flake.nixosModules.bach` is defined in `network.nix`, `users.nix` and `persistence.nix` under `modules/hosts/bach/`.

<details>
<summary>Why not a folder per service with one file per host?</summary>

A layout like `tailscale/{common,bach,satie}.nix` works, thanks to the merging above, but it scatters each host across every service folder. "What's special about bach?" is the question asked when bach is down, so it should be the cheapest to answer. Most services also run on one host only, where the extra folder is ceremony.

</details>

## Hosts

`modules/hosts/<host>/default.nix` defines `flake.nixosConfigurations.<host>` and lists the aspects that host runs. That list is the only switch: importing an aspect turns it on, removing it turns it off. There are no custom `enable` options.

When a feature differs between hosts, it splits by role, not by host. Tailscale is an example: `tailscale` (in `modules/base/`) runs on every host, and `tailnet-server` (in `modules/services/`) adds the server parts, Tailscale SSH and the open UDP port, on bach only.

A host folder holds only what's about that machine:

| File | Registers | Contents |
|---|---|---|
| `default.nix` | `nixosConfigurations.<host>` | the aspect list and a few host basics inline |
| `hardware.nix` (+ `zfs.nix` on bach) | `<host>-hardware` | boot, filesystems, kernel |
| `network.nix`, `users.nix`, `persistence.nix`, `eduroam.nix` | `<host>` or its own aspect | networking, users and home-manager, secrets |

The host basics stay inline in `default.nix` on purpose. List options like `environment.systemPackages` are ordered by module depth, so moving them into a deeper module changes the system's hash even when nothing else changes.

<details>
<summary>Why not custom enable options?</summary>

Importing an aspect is already the switch. An `enable` option per aspect would add a second one next to the import list.

</details>

<details>
<summary>Why not a framework on top of dendritic, like den?</summary>

Those formalise relationships between many users and many hosts. With two hosts and one user, plain flake-parts is enough.

</details>

## Folders

```
flake.nix          flake-parts entry
env.nix            shared settings, passed to every module as `env`
modules/
  hosts/<host>/    one folder per machine
  base/            every host: core, michele, ssh, tailscale, impermanence
  desktop/         desktop, niri, noctalia, gtk, xdg, zen, ghostty, screenshot, pcmanfm
  dev/             git, fish (with `update`), nvim, claude
  services/        one file per service, plus tailnet-server
secrets/           agenix secrets, and git-agecrypt values in secrets/sensitive/
scripts/           helpers for secrets
docs/              this site
```

## env.nix

`env.nix` holds settings shared across modules: `cloudSettings` (domains, service ports and subdomains) and `userSettings.<host>` (users, ssh key paths and public keys, network). Each host's `default.nix` imports it and passes it to NixOS modules through `specialArgs`, as `env`. bach also passes it to home-manager through `extraSpecialArgs` (`modules/hosts/bach/users.nix`); satie doesn't, and the fish home module (`modules/dev/fish.nix`) imports `env.nix` itself.

Some values in it are read from `secrets/sensitive/*.age`, which git-agecrypt decrypts in the working tree. See [Secrets](secrets.md).

## Refactors

A change that's meant to only restructure code must not change what gets built. To prove it, compare the system's derivation path before and after, for every host:

```sh
nix eval --raw .#nixosConfigurations.bach.config.system.build.toplevel.drvPath
nix eval --raw .#nixosConfigurations.satie.config.system.build.toplevel.drvPath
```

Identical paths mean nothing changed. Two things break this without changing behaviour: moving a list definition to a different module depth (see Hosts above), and renaming an asset file, since file names are part of store paths. A commit that touches `docs/` changes bach's path too, and one that touches `docs/shell.md` (also the man page, see [Shell reference](shell.md)) changes satie's, so keep docs edits out of refactor commits.

[flake-parts]: https://flake.parts
[import-tree]: https://github.com/vic/import-tree
