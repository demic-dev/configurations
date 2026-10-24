# Desktop on satie

satie is an M1 MacBook on Asahi Linux with 8 GB of RAM, running niri with the Noctalia shell. This page covers the session, the workspaces, memory, and the hardware workarounds.

## Session

The greeter is Noctalia's (`services.displayManager.noctalia-greeter` in `modules/desktop/noctalia.nix`). After login, niri starts with Noctalia as its bar, launcher and lock screen. Both are aspects with a system half and a home half in one file (`modules/desktop/niri/default.nix`, `modules/desktop/noctalia.nix`). niri's own config is `modules/desktop/niri/config.kdl`, linked into `~/.config/niri/`.

At login, niri opens two terminals, both fullscreen: nvim on `~/notes` in the notes workspace, and a plain Ghostty in term. Nothing else starts on its own.

Both terminals start two seconds after the session. Started together with it, Ghostty exits without an error. Their logs go to `$XDG_RUNTIME_DIR/ghostty-login.log`.

## Workspaces

niri's workspaces are dynamic by default and get renumbered as they empty. satie declares four named ones, which always exist, in this order:

| Key | Workspace | Opens there |
|---|---|---|
| Mod+1 | term | the login terminal |
| Mod+2 | notes | Ghostty with app-id `dev.michele.notes` (nvim on `~/notes`) |
| Mod+3 | browser | Zen (`zen-beta`) |
| Mod+4 | spotify | spotifast |

Mod+5 to Mod+0 go to ordinary dynamic workspaces below them. Mod+Shift+number moves the focused column there.

The notes terminal is told apart from other Ghostty windows by its app-id, set with `--class`. Only terminals opened at login are fullscreen; later ones open normally (`at-startup=true` in the window rule).

Mod+S starts spotifast, a Spotify client from the fastpotify flake. Its tests are skipped in `modules/hosts/satie/users.nix`, because they rebuild the whole crate with thin LTO and double the build time.

<details>
<summary>Why not a lighter compositor?</summary>

niri and Noctalia together use about 160 MB, around 6% of what a session uses. sway with waybar would save about 100 MB, which isn't worth a different way of working. A switch would be about behaviour (scrolling vs tiling, multiple monitors), not memory.

</details>

## Memory

8 GB is tight with a browser, Electron apps and a couple of Claude Code sessions. Swap is zram first, plus a 10 GB swapfile at `/var/lib/swapfile` as a slower fallback (`modules/hosts/satie/hardware.nix`). zram is a compressed swap device in RAM: idle pages typically compress to a third or a quarter of their size, and the kernel uses it before the swapfile because of its higher priority.

The Asahi kernel uses 16 KB pages instead of 4 KB, so the same program uses a bit more memory here than on an x86 laptop.

Zen unloads tabs when memory runs low (`browser.tabs.unloadOnLowMemory` in `modules/desktop/zen.nix`). Zen's own `zen.tab-unloader.*` settings have done nothing since Zen 1.23.

`free`'s "used" also counts GPU buffers, since the GPU shares system RAM, and kernel caches. The number to watch is "available".

## Bitwarden

The Bitwarden desktop app needs three workarounds, all in `modules/desktop/desktop.nix` and the satie host file:

- It's installed through home-manager, so its polkit action lands where the system polkit daemon doesn't look. A small package copies the action into the system profile.
- Its biometric setup writes a policy file to `/usr/share/polkit-1/actions`, which is read-only on NixOS. A tmpfiles rule places that file in advance, so the app skips the write.
- A polkit rule approves its unlock for the active local session, so it opens unlocked without a prompt.

It also needs an insecure Electron (`permittedInsecurePackages` in `modules/hosts/satie/default.nix`), until Bitwarden ships Electron 41 ([nixpkgs#526914](https://github.com/NixOS/nixpkgs/issues/526914)).

## Hardware workarounds

All in `modules/hosts/satie/hardware.nix` unless noted.

- After resume, the speakers come back in an error state, and PipeWire never retries them. A resume hook restarts the user's PipeWire and WirePlumber.
- Bluetooth headphones reconnect in the headset profile, with no output. WirePlumber is set to prefer AAC and to force A2DP (`modules/desktop/desktop.nix`).
- The Wi-Fi driver runs with roaming and two firmware features off (`brcmfmac.roamoff=1`, `brcmfmac.feature_disable=0x82000`).
- logind ignores the power key (`modules/desktop/desktop.nix`).

## Local search

hister indexes visited pages for full-text search on port 4433 (`modules/services/hister.nix`). Its semantic search gets embeddings from llama-cpp on `localhost:8080` (`modules/services/llama-cpp.nix`). llama-cpp is commented out in satie's list for now, so semantic search has no backend until it's re-enabled.
