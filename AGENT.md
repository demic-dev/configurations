# AGENT.md

Mandatory instructions. Read before every task in this repository.

## What this is

My personal NixOS configuration: one dendritic flake for all my machines.

- **`bach`**: aarch64-linux VPS. Self-hosted services (Nextcloud + OnlyOffice, Immich, Miniflux,
  Calibre-Web, Hugo, static files; Ghost configured but off). Encrypted ZFS with remote unlock in
  the initrd (port 2222), tmpfs root + impermanence. nginx is tailnet-only by default: a public vhost
  opts in with `allow all; ssl_verify_client on;` (Cloudflare only). SSH is Tailscale SSH.
- **`satie`**: aarch64-linux Apple-Silicon (Asahi) laptop. niri + noctalia desktop.

Both are aarch64. Don't build x86_64 outputs locally.

## How it is wired

[flake-parts] + [import-tree]: **every `.nix` under `./modules` is auto-imported**. There is no
import list to maintain. Non-`.nix` files (assets) are ignored and sit next to the module using them.

A file under `modules/` does one of two things:

1. **Registers an aspect**: `flake.nixosModules.<name>` and/or `flake.homeModules.<name>`: a
   self-contained piece of config, one file per *thing*. If a feature has a system half and a home
   half, both are in that file (e.g. `modules/desktop/niri/default.nix`). `modules/services/immich.nix`
   carries everything Immich needs (nginx vhost, postgres, redis, backup, persistence).
   Registering does nothing on its own.
2. **Assembles a host**: `modules/hosts/<host>/default.nix` lists the aspects that machine runs.
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
secrets/               agenix + git-agecrypt (see docs/secrets.md)
docs/                  the documentation (mdBook, served on the tailnet)
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

- Add one only if the code is genuinely inexplicable without it: a non-obvious workaround, an
  upstream bug, a subtle ordering constraint.
- Explain the **why**, never the **what**. If it restates the code, delete it.
- One or two lines. Never a paragraph. Never a section header or a banner.
- Do not comment out code as documentation, and do not narrate your changes in the file.

## Docs

`docs/` is the documentation for humans, built with mdBook by `modules/services/docs.nix` and served on the tailnet. `SUMMARY.md` lists the pages in order; a page that isn't listed there isn't rendered.

**A commit that changes behaviour updates the docs in the same commit.** Pages cite the files they describe as plain paths, so `rg 'modules/services/immich.nix' docs/` finds every page to check. Keep docs edits out of refactor commits: they change bach's drvPath. To catch up on commits that skipped this, use the `docs-sync` skill.

Writing rules for `docs/`:

- Describe the system as it is now, like the docs of a public library. No history, no dates, no "we changed X".
- "Why not" blocks are rare. Write one only for a real design decision, where a serious alternative was weighed and rejected for a reason that still holds (deny-by-default vs an allow list per vhost, zram vs swap on a zvol). Never for implementation details, workarounds or choices made in passing while writing the code. Format: right after the setting, `<details>`, `<summary>Why not X?</summary>`, a short paragraph, `</details>`.
- Impersonal voice for explanations ("The ARC is capped at 1 GiB"). Imperative for steps ("Run `unlock-bach` after a reboot").
- The reader knows NixOS and has a CS undergraduate background (git, networking, VPNs, filesystems). Don't explain flakes, modules or home-manager. Explain niche things (the ZFS ARC, zram, Authenticated Origin Pulls) in one sentence where they first appear.
- Every page opens with one sentence saying what it covers. The rest follows the content.
- Headings are nouns ("Swap", "Public vhosts"); how-to sections use tasks ("Restore a few files").
- Repeat concrete values (1 GiB, port 2222) and name the file that sets them, as a plain path from the repo root.
- Nix snippets only when the exact shape is the point. Shell commands in code blocks, ready to copy.
- No bold except for warnings where data or access is at stake. No emoji. `> [!WARNING]` boxes, rarely.
- Human prose: short paragraphs, describe instead of selling, no filler, no recaps. Lists for real lists, tables for comparisons.
- Never use em dashes, here or anywhere else (commit messages included). Use commas, colons, parentheses or full stops.
- The repo is public: nothing git-agecrypt hides (domains, bach's public IP, repository URLs) and no names of people.

Preview while writing: `nix run nixpkgs#mdbook -- serve docs`.

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
