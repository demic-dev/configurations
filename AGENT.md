# AGENT.md

Mandatory instructions. Read before every task in this repository.

## What this is

My personal NixOS configuration: one dendritic flake for all my machines.

- **`bach`** — aarch64-linux VPS. Self-hosted services (Nextcloud, Immich, Ghost, Miniflux,
  Calibre-Web, Hugo), ZFS + impermanence with remote LUKS/ZFS unlock.
- **`satie`** — aarch64-linux Apple-Silicon (Asahi) laptop. niri + noctalia desktop.

Both are aarch64. Don't build x86_64 outputs locally.

## How it is wired

[flake-parts] + [import-tree]: **every `.nix` under `./modules` is auto-imported**. There is no
import list to maintain.

A file under `modules/` does one of two things:

1. **Registers an aspect** — `flake.nixosModules.<name>` (or `flake.homeModules.<name>`): a
   self-contained piece of config, e.g. `modules/nixos/services/immich.nix` carries everything
   Immich needs (nginx vhost, postgres, redis, backup, fail2ban). Registering does nothing on
   its own.
2. **Assembles a host** — `modules/hosts/<host>.nix` lists the aspects that machine runs. This
   is the only toggle surface: the import *is* the switch, there are no `enable` flags.

`env.nix` holds shared settings (`cloudSettings`, `userSettings.<host>`) and is threaded into
modules via `specialArgs`/`extraSpecialArgs` as `env`. Values under `secrets/sensitive/*.age`
are read through git-agecrypt's smudge filter; agenix secrets in `secrets/*.age` decrypt at
activation, never at evaluation.

```
flake.nix              flake-parts entry
env.nix                shared settings, passed as `env`
modules/hosts/         per-machine assembly + toggle surface
modules/nixos/         flake.nixosModules.<x>  (core, desktop, hardware/, services/, users/)
modules/home/          flake.homeModules.<x>   (git, shells/, desktop/)
disko/                 bach ZFS + impermanence
secrets/               agenix + git-agecrypt (see secrets/README.md)
docs/RECOVERY.md       disaster recovery
```

Common tasks:

- **Add a service or app** → new file registering `flake.nixosModules.<x>` /
  `flake.homeModules.<x>`, then add `<x>` to the host's module list.
- **Toggle a service** → comment or uncomment its name in that host's list.
- **Add a host** → `modules/hosts/<host>.nix` with `flake.nixosConfigurations.<host>`.

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
nix flake check                       # evaluate both configurations
nixos-rebuild switch --flake .#satie  # on the machine itself (`update` alias)
```

Never run `nixos-rebuild switch` for me unless I ask. Prefer evaluating over building when
checking a change.

[flake-parts]: https://flake.parts
[import-tree]: https://github.com/vic/import-tree
