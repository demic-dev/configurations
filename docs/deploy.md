# Build and deploy

How to evaluate, build and switch either host, and where builds run.

## Evaluate

Evaluate on satie. git-agecrypt decrypts `secrets/sensitive/` only in satie's checkout and in bach's `~/nixos`, which [automatic updates](#automatic-updates) use. `env.nix` reads those files at evaluation time. Anywhere else, bach's IP, domains and email come out as ciphertext, and bach evaluates into a broken system.

```sh
nix flake check
```

New files have to be `git add`ed before the flake sees them.

## Deploy

`update` is a fish function on every host (`modules/dev/fish.nix`). It wraps `nixos-rebuild`, and its defaults are: deploy to this host, build here, mode `switch`.

```sh
update                                # build here, switch this host
update -b bach                        # build on bach, switch this host
update -b bach -d bach                # build on bach, switch bach
update -d bach -m boot                # build here, make it bach's next boot
update -b bach -m test --show-trace   # other flags go to nixos-rebuild
```

When the target is another host, `update` asks for that host's sudo password locally and passes it over ssh, since sudo on the target has no terminal to prompt on. It logs in with michele's key, whose passphrase is asked once per run: nixos-rebuild shares one ssh connection for the whole run, and the `bach` entry in michele's ssh config (`modules/hosts/satie/users.nix`) adds the key to the ssh agent, so later runs don't ask. Remote builds and deploys use substitutes, so the remote side downloads from the caches instead of copying everything from here.

The usual way to deploy either host is to build on bach: `update -b bach` on satie, `update -b bach -d bach` for bach.

## Builds on bach

bach builds for both hosts, alongside its services. To keep builds from pushing the services out of memory, the nix-daemon runs with batch CPU scheduling and idle IO priority, and its cgroup is capped at 3 GiB of RAM plus 512 MiB of swap (`modules/hosts/bach/default.nix`). [Memory](bach/memory.md) explains the numbers.

A build that needs more than that fails instead of slowing bach down. spotifast's test phase (now skipped) was OOM-killed on bach, and calibre's duckdb dependency fails to build on bach (calibre is commented out in `modules/hosts/satie/users.nix`). Build those on satie: run plain `update` there.

satie's kernel and U-Boot (from nixos-apple-silicon, which follows our nixpkgs) aren't in cache.nixos.org, so bach compiles them whenever nixpkgs moves.

## Automatic updates

satie builds both hosts at night and switches itself. bach switches to the system satie built for it as soon as satie hands it over. Neither host reboots. Both halves are in `modules/services/auto-update.nix`, and each is a unit named `auto-update.service`.

nixpkgs moves to the newest commit that is newer than the one the hosts run and needs no heavy build (see below). The other inputs move to their newest commit. There is no delay: a commit reaches both hosts as soon as Hydra has built what they need from it.

### On satie

The unit starts every day at 03:00, only if satie is awake and on the charger (`ConditionACPower=true`). A night satie slept or ran on battery is skipped, not caught up during the day. It holds a sleep inhibitor, so noctalia's idle suspend waits for it; closing the lid still suspends.

The build runs as michele in a worktree of the checkout, `~/.local/state/auto-update/nixos`, detached at `main`, so it never touches the files you're working on:

1. Checks that switching won't roll back something you deployed by hand and haven't committed. A host passes if it runs what the last run gave it, if it switched before `main`'s newest commit (the time of `/run/current-system`), or if it runs what `main` builds. Otherwise it stops.
2. Picks the nixpkgs commit (see below) and builds both hosts. The journal gets a line `building '/nix/store/…drv'...` as each derivation starts building, so `journalctl -fu auto-update` shows what it's on.
3. Copies bach's system into bach's store with `nix copy --substitute-on-destination --no-check-sigs`: bach fetches what cache.nixos.org has itself, and only what satie built crosses the network. What satie built is unsigned; bach accepts it because michele is in `trusted-users` there (`modules/base/core.nix`). It logs in as michele with the `auto-update-at-satie` key, which bach accepts with `restrict` (no terminal, no forwarding).
4. Commits `flake.lock` as `chore(flake): update inputs` if it changed, on the branch `auto-update` of the checkout. When the checkout is on `main` with no changes, `main` fast-forwards to it; otherwise the commit waits on the branch and the journal says so. It never pushes: push the lock commits to GitHub as usual.
5. Writes the path of bach's new system to `~/.local/state/auto-update/for-bach` on bach.
6. As root, switches satie to the new system, then starts `cleanup.service`.

So a deploy followed by a commit, of that change or of anything else, passes. What stops the job is a deploy newer than `main`'s newest commit that `main` doesn't build: an experiment you deployed and haven't committed yet. An experiment deployed before your latest commit is rolled back; the change is still in your working tree, and the previous generation in the boot menu. The comparison with `main`'s build uses store paths, so a deploy from a dirty tree matches the commit that follows it, as long as `system.configurationRevision` stays unset. Something committed on `main` but never deployed is switched to by the next run.

A failure shows in the greeting's `failed` line; satie sends no mail.

### On bach

A path unit watches `~/.local/state/auto-update/for-bach`. When satie writes it, `auto-update.service` starts as root: if the path is a system for bach (its `etc/hostname` says `bach`) and not the one running, it switches to it, then starts `cleanup.service`. bach doesn't evaluate or build anything. A failure mails through `OnFailure=` (see [Health checks](bach/health.md)).

bach's clone `~/nixos` isn't updated by the job. Deploy bach from satie.

A new kernel on bach waits for a reboot by hand, since the pool needs `unlock-bach`. The shell greeting shows it on its `reboot` line (`modules/dev/fish.nix`).

### How the nixpkgs commit is picked

Some packages must come from the binary cache. They don't fit in memory (Chromium and Electron need far more than satie's 8 GB) or take hours to build: on 26 November electron 43.8.11 (for `bitwarden-desktop`) ran for hours on bach and was OOM-killed. The cache has a package only once Hydra has built it, and on aarch64-linux that can take days.

So the unit asks Hydra for the nixpkgs commits it has evaluated (`https://hydra.nixos.org/jobset/nixpkgs/unstable/evals`: the last 20, one every 8 to 9 hours) and goes through the ones newer than the commit the hosts run, newest first. For each one it runs `nix build --dry-run` for both hosts and takes the first whose plan builds none of the `heavy` list in `modules/services/auto-update.nix`:

- browser engines (Chromium, Electron, QtWebEngine, WebKitGTK) and the apps built on them (Signal, Bitwarden)
- compilers and runtimes (GCC, LLVM, Clang, rustc, GHC, Zig, OpenJDK, Node.js, pandoc)
- immich with onnxruntime and PyTorch, on bach

Each skipped commit gets a line in the journal, `skipping nixpkgs 5debd22, it would build:`, followed by what it would build. If no newer commit fits, the journal says `no newer nixpkgs commit fits, keeping 619c39f`: `flake.lock` stays as it is, and the run still builds and switches both hosts to `main`'s config.

Everything else is built on satie when needed: satie's Asahi kernel, u-boot, config files.

### Disk

Each candidate commit fetches its nixpkgs source, about 500 MB. bach's system and what it takes to build it pass through satie's store. None of that is kept: the out-link of bach's system is removed after the copy, and the `cleanup` after each switch keeps 2 system generations and collects garbage, on both hosts.

## After a reboot of bach

bach's disk is encrypted, and boot stops until the passphrase arrives over ssh. From satie:

```sh
unlock-bach
```

[Disk and boot](bach/disk.md) has the details.

## Housekeeping

On every host, the store is optimised daily at 04:00 (`modules/base/core.nix`).
Once a week, and after every automatic update, `cleanup.service` runs `cleanup` (`modules/base/cleanup.nix`, described in [Shell reference](shell.md)): it keeps the last 2 system generations and collects garbage.
Both timers are persistent: a run missed while the host was off or asleep happens once, soon after it wakes up.
During a build, Nix also collects garbage on its own when less than 10 GiB is free, until 30 GiB is free (`min-free` and `max-free` in `modules/base/core.nix`).
That only removes paths no generation uses.

Both hosts empty `/tmp` at boot (`boot.tmp.cleanOnBoot`), so GC roots left there by builds and agent sessions disappear with it.
