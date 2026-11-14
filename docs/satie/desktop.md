# Desktop on satie

satie is an M1 MacBook on Asahi Linux with 8 GB of RAM, running niri with the Noctalia shell. This page covers the session, the workspaces, memory, and the hardware workarounds.

## Session

The greeter is Noctalia's (`services.displayManager.noctalia-greeter` in `modules/desktop/noctalia.nix`). After login, niri starts with Noctalia as its bar, launcher and lock screen. Both are aspects with a system half and a home half in one file (`modules/desktop/niri/default.nix`, `modules/desktop/noctalia.nix`). niri's own config is `modules/desktop/niri/config.kdl`, linked into `~/.config/niri/`.

At login, niri starts the Bitwarden desktop app and opens two terminals, both fullscreen: nvim on `~/notes` in the notes workspace, and a plain Ghostty in term. Nothing else starts on its own. Three seconds after the session starts, caffeine is switched on (`modules/desktop/niri/config.kdl`), so the screen does not blank or lock on idle until it is switched off. Noctalia does not remember the state across restarts.

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

## Dictation

The microphone key on the function row (F5 without Fn, `XF86AudioMicMute`) starts dictation: a short sound, then recording. Recording stops after 1.5 seconds of silence, or on a second press of the key. A second sound marks the stop, and the whole clip is transcribed and typed at the cursor with `wtype`, followed by a space so the next dictation starts cleanly, and never by Enter. Mic mute has no key.

Everything runs on satie, on the CPU. The model is Moonshine v2 Medium (Q8_0 GGUF, 296 MB) run with transcribe.cpp, built in the same file. It only loads while a clip is transcribed: a 10 second clip takes about 1.5 to 2 seconds and up to 640 MB of RAM. English only. The recording sits in `$XDG_RUNTIME_DIR` and is deleted afterwards.

Silence ends the recording when the level stays below 1% of full scale. A clip that never crosses that level is not transcribed, so pressing the key and saying nothing types nothing. A muted microphone, a missing one or a failed transcription shows a notification instead.

The pause length (`pauseSeconds`) and the model (`model`) are the two values at the top of `modules/desktop/dictation.nix`. The binding is in `modules/desktop/niri/config.kdl`. Recording and transcribing, without the typing, is `listen`, and the transcriber alone is `wav2text` (see `docs/shell.md`).

## Voice commands

Saying "hey linux", or pressing Mod + the microphone key, runs `voice`. It records and transcribes like dictation, then runs one command from a list instead of typing: "pause the music" or "go to the notes" runs the line of the list that matches best. The recording stops after 0.8 seconds of silence, shorter than dictation's pause because a command is one breath. A second press of the microphone key, with or without Mod, stops the recording.

The list is `modules/desktop/voice-commands.tsv`, installed as `~/.config/voice/commands.tsv`. Each line is a description, a tab, then a shell command. The line whose command is `false` stands for "none of these". The file holds at most 26 lines, because the model answers with one letter per line.

The line is picked by OneJev 1.6 0.8B (Q8_0 GGUF, 812 MB), a small model trained to answer a multiple-choice question with a single letter, run by llama.cpp's `llama-server`. `voice-pick` starts the server for one question and stops it again, which takes about a second and up to 1.8 GB of RAM. It sends the transcript and the descriptions, and reads the probability the model gives to each letter. The model never writes a command: what runs is the text of the chosen line, started through `niri msg action spawn-sh`, the way a key bind starts it. Everything stays on satie.

The feedback is Noctalia's OSD. Its "microphone active" popup shows when the recording starts, and once the clip is transcribed `voice` shows the transcript in a popup of its own (`noctalia msg osd-show`), which stays up while the model picks.

Nothing runs when the model gives the "none of these" line a probability above 0.15, or when that line is the best one. A notification shows the transcript instead. The probability of the best line is not what decides: two lines that fit about equally ("go to the terminal" against "the first terminal") split it between them, while a sentence that is no command always puts weight on "none of these". The limit (`voiceNoneMax`), the pause (`voicePauseSeconds`) and the model (`voiceModel`) are at the top of `modules/desktop/dictation.nix`.

### Wake word

`wake` is a user service that keeps the microphone open and runs a keyword spotter on it, a small speech model (3.3M parameters, from sherpa-onnx) that only reports when a given phrase is spoken. The audio comes from `pw-record`, under the PipeWire application name `wake`. When it hears "hey linux" it starts `voice`, so the command is spoken after the start sound. It takes about 12% of one efficiency core (it is pinned to CPUs 0-3) and about 100 MB of RAM.

A detection is ignored while the session is locked, while a recording is already running (a dictation is not cut off by the phrase), and while the previous `voice` has not finished. The lock state is logind's `LockedHint`, which Noctalia's lock screen sets. Anything other than a clear "not locked" counts as locked.

That application name is left out of Noctalia's microphone indicator (`shell.privacy.mic_filter_regex`, set in the same file). Otherwise the indicator would stay lit, and the "microphone active" popup would never show for a recording, since the microphone would never go from idle to active.

Muting the microphone switches the wake word off, since the spotter then hears silence. So does stopping the service, until the next login:

```sh
systemctl --user stop wake
```

The phrase (`wakeWord`), its boost (`wakeBoost`) and its threshold (`wakeThreshold`) are at the top of `modules/desktop/dictation.nix`. The phrase is written in the model's subword pieces, and the comment above it has the command that converts a new one. A lower threshold or a higher boost makes it trigger more easily, on the phrase and on phrases that sound like it.

### Add a command

Add a line to `modules/desktop/voice-commands.tsv`. The description is all the model sees, so write it with the words that would be spoken, and separate synonyms with commas. Try a phrase against the edited file without deploying:

```sh
echo "skip this one" | voice-pick modules/desktop/voice-commands.tsv
```

`modules/desktop/voice-tests.tsv` holds spoken phrases with the command each one should run, or `false` for a sentence that should run nothing. Add a few phrases for the new line, then run them all:

```sh
voice-pick --test modules/desktop/voice-tests.tsv modules/desktop/voice-commands.tsv
```

It prints the phrases that were refused or that ran another command, each with the probability of the "none of these" line, then the probability and the command of its best line, and the totals at the end. Deploy once the new phrases pass and no sentence marked `false` runs anything.

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

With "Require master password on app restart" unticked in its settings, the app stores its unlock key in gnome-keyring, which PAM starts and unlocks with the login password (`security.pam.services.greetd.enableGnomeKeyring` in `modules/desktop/desktop.nix`). After login, the polkit rule and that key unlock the app without the master password. This needs Bitwarden 2026.10.2 or later.

Zen's Bitwarden extension talks to the app through native messaging: Zen runs the app's `desktop_proxy`, found through `~/.mozilla/native-messaging-hosts/com.8bit.bitwarden.json`. The app writes that manifest itself at every start, before it opens the socket the proxy connects to, so the file must stay writable: a read-only manifest from Nix makes the write fail and the app never listens. The connection needs "Allow browser integration" on in the app's settings and "Unlock with biometrics" on in the extension's.

## Hardware workarounds

All in `modules/hosts/satie/hardware.nix` unless noted.

- After resume, the speakers come back in an error state, and PipeWire never retries them. A resume hook restarts the user's PipeWire and WirePlumber.
- Bluetooth headphones reconnect in the headset profile, with no output. WirePlumber is set to prefer AAC and to force A2DP (`modules/desktop/desktop.nix`).
- The Wi-Fi driver runs with roaming and two firmware features off (`brcmfmac.roamoff=1`, `brcmfmac.feature_disable=0x82000`).
- logind ignores the power key (`modules/desktop/desktop.nix`).

## Local search

hister indexes visited pages for full-text search on port 4433 (`modules/services/hister.nix`). Its semantic search gets embeddings from llama-cpp on `localhost:8080` (`modules/services/llama-cpp.nix`). Both are commented out in satie's lists for now (`modules/hosts/satie/users.nix`, `modules/hosts/satie/default.nix`).
