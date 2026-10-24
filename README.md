# configurations

One NixOS flake for my machines, built with the dendritic pattern ([flake-parts] and [import-tree]).

- bach: an aarch64 VPS running my self-hosted services (Nextcloud, Immich, Miniflux, calibre-web, a Hugo site). Encrypted ZFS, a root wiped at every boot, everything private to the tailnet except what has to be public.
- satie: an M1 MacBook on Asahi Linux, with niri and Noctalia.

The documentation is in [`docs/`](docs/): how the flake is wired, how each host is set up and why, and how to recover from losing a machine. It's also served as a site on my tailnet.

## Quick reference

```sh
nix flake check            # evaluate both hosts (on satie: secrets/sensitive/ must be decrypted)
update -b bach             # build on bach, switch this host
update -b bach -d bach     # build on bach, switch bach
unlock-bach                # type bach's disk passphrase after a reboot
```

## References

1. [Dendritic pattern](https://github.com/mightyiam/dendritic)
2. [carjorvaz/nixos](https://github.com/carjorvaz/nixos)
3. [diogotcorreia/dotfiles](https://github.com/diogotcorreia/dotfiles)
4. [librephoenix/nixos-config](https://github.com/librephoenix/nixos-config)
5. [Baitinq/nixos-config](https://github.com/Baitinq/nixos-config)

[flake-parts]: https://flake.parts
[import-tree]: https://github.com/vic/import-tree
