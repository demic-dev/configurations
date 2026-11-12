{ ... }:
let
  pauseSeconds = "1.5";
  model = {
    url = "https://huggingface.co/handy-computer/moonshine-streaming-small-gguf/resolve/e53f28b0cb90308390c852068b950a1aadd238b0/moonshine-streaming-small-Q8_0.gguf";
    hash = "sha256-0DZw9pYptkkIXQ9Epj2XZotBGRF8yWEaTkrZQ0FxPfw=";
  };
in
{
  flake.homeModules.dictation =
    { pkgs, ... }:
    let
      transcribe-cpp = pkgs.stdenv.mkDerivation {
        pname = "transcribe-cpp";
        version = "0.4.2";
        src = pkgs.fetchFromGitHub {
          owner = "handy-computer";
          repo = "transcribe.cpp";
          tag = "v0.4.2";
          hash = "sha256-6zEPd1DA9A19l9rUPzY5SRz5nmQZN/3cDzqbwOG02A0=";
        };
        nativeBuildInputs = [ pkgs.cmake ];
        buildInputs = [ pkgs.openblas ];
        cmakeFlags = [
          "-DTRANSCRIBE_BUILD_TESTS=OFF"
          # ggml turns GGML_NATIVE off in Nix builds; the M1's dotprod and fp16 halve the encoder time.
          "-DGGML_CPU_ARM_ARCH=armv8.2-a+dotprod+fp16"
        ];
        installPhase = "install -Dm755 bin/transcribe-cli $out/bin/transcribe-cli";
      };

      wav2text = pkgs.writeShellApplication {
        name = "wav2text";
        runtimeInputs = [ pkgs.util-linux ];
        text = ''
          # CPUs 4-7 are the M1's performance cores: about 20% faster than letting threads land on the others.
          # -o truncates what it opens, so fd 3 is a pipe and `wav2text a.wav >> notes` can't wipe notes.
          taskset -c 4-7 ${transcribe-cpp}/bin/transcribe-cli -q --threads 4 \
            -m ${pkgs.fetchurl model} -o /dev/fd/3 "$1" 3>&1 >/dev/null | cat
        '';
      };

      dictate = pkgs.writeShellApplication {
        name = "dictate";
        runtimeInputs = with pkgs; [
          libnotify
          pipewire
          sox
          wav2text
          wireplumber
          wtype
        ];
        text = ''
          pidfile="$XDG_RUNTIME_DIR/dictate.pid"
          if [ -f "$pidfile" ] && kill -INT "$(cat "$pidfile")" 2>/dev/null; then
            exit 0
          fi

          fail() {
            notify-send -u critical Dictation "$1"
            exit 1
          }

          case "$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>&1)" in
            *MUTED*) fail "The microphone is muted" ;;
            Volume:*) ;;
            *) fail "No microphone" ;;
          esac

          wav=$(mktemp -p "$XDG_RUNTIME_DIR" --suffix=.wav dictate-XXXXXX)
          trap 'rm -f "$wav"' EXIT
          sounds=${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo

          # Played before recording starts, so the microphone doesn't take it for speech.
          pw-play "$sounds/device-added.oga"
          sox -q -t pulseaudio default -r 16000 -c 1 -b 16 "$wav" \
            silence 1 0.1 1% 1 ${pauseSeconds} 1% &
          echo $! > "$pidfile"
          wait $! || fail "Recording failed"
          rm -f "$pidfile"
          pw-play "$sounds/device-removed.oga" &

          # sox only writes once the level crosses 1%, so no speech means no samples.
          [ "$(soxi -s "$wav")" -gt 0 ] || exit 0
          text=$(wav2text "$wav") || fail "Transcription failed"
          [ -n "$text" ] || exit 0
          wtype -- "$text"
        '';
      };
    in
    {
      home.packages = [
        dictate
        wav2text
      ];
    };
}
