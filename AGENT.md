# AGENT.md

Mandatory instructions. Read before every task in this repository.

## What this is

My personal NixOS configuration: one dendritic flake for all my machines.

- **`bach`** — aarch64-linux VPS. Self-hosted services (Nextcloud + OnlyOffice, Immich, Miniflux,
  Calibre-Web, Hugo, static files; Ghost configured but off). Encrypted ZFS with remote unlock in
  the initrd (port 2222), tmpfs root + impermanence. Only 80/443 are public; SSH is Tailscale SSH.
- **`satie`** — aarch64-linux Apple-Silicon (Asahi) laptop. niri + noctalia desktop.

Both are aarch64. Don't build x86_64 outputs locally.

## How it is wired

[flake-parts] + [import-tree]: **every `.nix` under `./modules` is auto-imported**. There is no
import list to maintain. Non-`.nix` files (assets) are ignored and sit next to the module using them.

A file under `modules/` does one of two things:

1. **Registers an aspect** — `flake.nixosModules.<name>` and/or `flake.homeModules.<name>`: a
   self-contained piece of config, one file per *thing*. If a feature has a system half and a home
   half, both are in that file (e.g. `modules/desktop/niri/default.nix`). `modules/services/immich.nix`
   carries everything Immich needs (nginx vhost, postgres, redis, backup, fail2ban, persistence).
   Registering does nothing on its own.
2. **Assembles a host** — `modules/hosts/<host>/default.nix` lists the aspects that machine runs.
   This is the only toggle surface: the import *is* the switch, there are no `enable` flags.

`env.nix` holds shared settings (`cloudSettings`, `userSettings.<host>`) and is threaded into
modules via `specialArgs`/`extraSpecialArgs` as `env`. Values under `secrets/sensitive/*.age`
are read through git-agecrypt's smudge filter; agenix secrets in `secrets/*.age` decrypt at
activation, never at evaluation.

```
flake.nix              flake-parts entry
env.nix                shared settings, passed as `env`
modules/hosts/<host>/  default.nix (nixosConfigurations, aspect list, host basics),
                       hardware.nix/zfs.nix (<host>-hardware), network/users/… (<host> aspect)
modules/base/          every host: core, michele, ssh, tailscale, impermanence
modules/desktop/       niri, noctalia, gtk, xdg, zen, ghostty, …
modules/dev/           git, fish (incl. `update`), nvim, claude
modules/services/      one file per service, plus tailnet-server
secrets/               agenix + git-agecrypt (see secrets/README.md)
docs/RECOVERY.md       disaster recovery
```

Common tasks:

- **Add a service or app** → new file registering `flake.nixosModules.<x>` /
  `flake.homeModules.<x>`, then add `<x>` to the host's list (`hosts/<host>/default.nix` for NixOS,
  `hosts/<host>/users.nix` for home-manager).
- **Toggle a service** → comment or uncomment its name in that host's list.
- **Add a host** → `modules/hosts/<host>/` with a `default.nix` defining `flake.nixosConfigurations.<host>`.
- **Persist state** → `environment.persistence."/persist"` lines go in the service's own file.
  Hosts without `/persist` (satie) import `impermanence` with that location disabled.

## Rules for the code you write

**Keep it simple. This is the rule that overrides everything else.**

- No overengineering. Solve exactly what I asked, nothing more. No speculative options, no
  future-proofing, no configurability I did not ask for.
- No overabstraction. Prefer plain, literal NixOS/home-manager config over `let` helpers,
  generator functions, `mkMerge` gymnastics or custom module options. A little repetition beats
  a clever abstraction.
- Use upstream nixpkgs options instead of hand-rolling systemd units, scripts or wrappers.
- Match the surrounding file's style and naming.

**Comments: fewer than the minimum.**

- Add one only if the code is genuinely inexplicable without it — a non-obvious workaround, an
  upstream bug, a subtle ordering constraint.
- Explain the **why**, never the **what**. If it restates the code, delete it.
- One or two lines. Never a paragraph. Never a section header or a banner.
- Do not comment out code as documentation, and do not narrate your changes in the file.

## Verifying

```bash
nix flake check                                                       # evaluate both configurations
nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath
```

- **Evaluate on satie.** Only its checkout has git-agecrypt decrypting `secrets/sensitive/`;
  elsewhere those values are ciphertext. New files must be `git add`ed before the flake sees them.
- **Pure refactors must be proven no-ops**: identical drvPath for both hosts before and after.
  List options (e.g. `environment.systemPackages`) are ordered by module depth, so moving a list
  definition into a deeper module changes the hash. That's why the host basics stay inline in
  `hosts/<host>/default.nix`. Asset file names are part of store paths: don't rename them in a refactor.
- Deploying is `update [-b build-host] [-d deploy-host] [-m switch|boot|test|…]` (`modules/dev/fish.nix`).
  Never run `nixos-rebuild switch` (or `update`) for me unless I ask. Prefer evaluating over
  building when checking a change.

[flake-parts]: https://flake.parts
[import-tree]: https://github.com/vic/import-tree
