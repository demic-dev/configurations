# Build and deploy

How to evaluate, build and switch either host, and where builds run.

## Evaluate

Evaluate on satie. git-agecrypt only decrypts `secrets/sensitive/` in satie's checkout, and `env.nix` reads those files at evaluation time. Anywhere else, bach's IP, domains and email come out as ciphertext, and bach evaluates into a broken system.

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

When the target is another host, `update` asks for that host's sudo password locally and passes it over ssh, since sudo on the target has no terminal to prompt on. Remote builds and deploys use substitutes, so the remote side downloads from the caches instead of copying everything from here.

The usual way to deploy either host is to build on bach: `update -b bach` on satie, `update -b bach -d bach` for bach.

## Builds on bach

bach builds for both hosts, alongside its services. To keep builds from pushing the services out of memory, the nix-daemon runs with batch CPU scheduling and idle IO priority, and its cgroup is capped at 3 GiB of RAM plus 512 MiB of swap (`modules/hosts/bach/default.nix`). [Memory](bach/memory.md) explains the numbers.

A build that needs more than that fails instead of slowing bach down. spotifast's test phase (now skipped) was OOM-killed on bach, and calibre's duckdb dependency fails to build on bach (calibre is commented out in `modules/hosts/satie/users.nix`). Build those on satie: run plain `update` there.

Every host trusts the nixos-apple-silicon cache (`modules/base/core.nix`). bach needs it too, because it builds satie: without it, bach would compile the Asahi kernel from source.

## The Asahi pin

satie's kernel and U-Boot are only cached when built against the exact nixpkgs that nixos-apple-silicon's CI used. `flake.nix` pins `nixpkgs-asahi` to that revision, and `hardware.asahi.pkgs` (`modules/hosts/satie/hardware.nix`) builds just those two packages from it. The rest of satie follows the main nixpkgs.

To update it, read the nixpkgs revision from nixos-apple-silicon's own `flake.lock` and set `nixpkgs-asahi` to it in the same commit that bumps nixos-apple-silicon. Never let it float.

## After a reboot of bach

bach's disk is encrypted, and boot stops until the passphrase arrives over ssh. From satie:

```sh
unlock-bach
```

[Disk and boot](bach/disk.md) has the details.

## Housekeeping

On every host (`modules/base/core.nix`), the store is optimised daily at 04:00, and garbage collection runs weekly and deletes generations older than 15 days.
