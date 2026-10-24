# Introduction

This is the documentation for one NixOS flake that configures two machines. It explains how the configuration is put together, why it's set up the way it is, and how to work with it.

## Hosts

| Host | Hardware | Role |
|---|---|---|
| bach | aarch64 VPS, 8 GB RAM | Self-hosted services, builds for both hosts |
| satie | Apple Silicon laptop (Asahi), 8 GB RAM | Desktop and development |

Both are aarch64-linux, so either can build for the other without emulation. satie has to stay fully usable with bach down.

## Services on bach

| Service | Reachable from |
|---|---|
| Website (Hugo) and its `www` alias | internet |
| Static files                             | internet |
| Immich | share links from the internet, the app on the tailnet |
| calibre-web | the OPDS feed from the internet, the web UI on the tailnet |
| Nextcloud, with OnlyOffice for documents | tailnet |
| Miniflux | tailnet |
| These docs | tailnet |

Everything public goes through Cloudflare. Everything else is denied by nginx unless the request comes from the tailnet. [Network and exposure](bach/network.md) explains how.

Ghost is configured in `modules/services/ghost.nix` but not imported, so it's off. Docker lives in the same file and is off with it.

## Reading these docs

The pages describe the configuration as it is now. Where an obvious alternative was considered and rejected, a collapsed "Why not" block next to the setting says why.

Paths are relative to the repository root. Values quoted in a page (sizes, ports, times) come from the file named next to them, which is the source of truth if the two ever disagree.

The source of this site is `docs/`. To preview changes while editing, on satie:

```sh
nix run nixpkgs#mdbook -- serve docs
```
