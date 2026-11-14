{ ... }:
let
  pauseSeconds = "1.5";
  model = {
    url = "https://huggingface.co/handy-computer/moonshine-streaming-medium-gguf/resolve/56302cde2ae162d1357a833d91775bcd06e91e1b/moonshine-streaming-medium-Q8_0.gguf";
    hash = "sha256-98lWQkm1CPYBKSfsT55TYIfaU6cEf4WMqZdb6l91KZ4=";
  };
  voicePauseSeconds = "0.4";
  voiceIdleSeconds = "20";
  voiceNoneMax = "0.15";
  voiceModel = {
    url = "https://huggingface.co/mradermacher/OneJev1.6-0.8B-GGUF/resolve/54f205a532e283f1b0697d78891f6968c57c3ebc/OneJev1.6-0.8B.Q8_0.gguf";
    hash = "sha256-EiXE+NkHY2wtRyWuXKM6K6MqZOhO/GoJBSg5eQlws64=";
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

      listen = pkgs.writeShellApplication {
        name = "listen";
        runtimeInputs = with pkgs; [
          libnotify
          pipewire
          sox
          wav2text
          wireplumber
        ];
        text = ''
          pidfile="$XDG_RUNTIME_DIR/listen.pid"
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

          wav=$(mktemp -p "$XDG_RUNTIME_DIR" --suffix=.wav listen-XXXXXX)
          trap 'rm -f "$wav"' EXIT
          sounds=${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo

          # Played before recording starts, so the microphone doesn't take it for speech.
          pw-play "$sounds/device-added.oga"
          sox -q -t pulseaudio default -r 16000 -c 1 -b 16 "$wav" \
            silence 1 0.1 1% 1 "''${1:-${pauseSeconds}}" 1% &
          echo $! > "$pidfile"
          wait $! || fail "Recording failed"
          rm -f "$pidfile"
          pw-play "$sounds/device-removed.oga" &

          # sox only writes once the level crosses 1%, so no speech means no samples.
          [ "$(soxi -s "$wav")" -gt 0 ] || exit 0
          wav2text "$wav" || fail "Transcription failed"
        '';
      };

      dictate = pkgs.writeShellApplication {
        name = "dictate";
        runtimeInputs = [
          listen
          pkgs.wtype
        ];
        text = ''
          text=$(listen)
          [ -n "$text" ] || exit 0
          wtype -- "$text "
        '';
      };
      # nodejs as in modules/services/llama-cpp.nix. On the GPU a pick takes 1 s, on the CPU 1.5 s.
      llama = pkgs.llama-cpp.override {
        nodejs_latest = pkgs.nodejs_24;
        vulkanSupport = true;
      };

      voice-pick = pkgs.writeShellApplication {
        name = "voice-pick";
        runtimeInputs = with pkgs; [
          curl
          jq
          libnotify
          llama
        ];
        text = ''
          tests=
          if [ "''${1:-}" = --test ]; then
            tests=$2
            shift 2
          fi
          file=''${1:-''${XDG_CONFIG_HOME:-$HOME/.config}/voice/commands.tsv}
          if [ "$(grep -c "" "$file")" -gt 26 ]; then
            notify-send -u critical "Voice control" "$file has more than 26 lines"
            echo "voice-pick: $file has more than 26 lines" >&2
            exit 2
          fi

          # The model holds 1.8 GB, so the server only lives as long as this script.
          dir=$(mktemp -d -p "$XDG_RUNTIME_DIR" voice-XXXXXX)
          llama-server --host "$dir/llama.sock" -m ${pkgs.fetchurl voiceModel} --n-gpu-layers 99 \
            --ctx-size 2048 --fit off --no-warmup --cache-ram 0 --no-webui >/dev/null 2>&1 &
          server=$!
          trap 'kill $server; rm -rf "$dir"' EXIT
          until curl -sf --unix-socket "$dir/llama.sock" http://localhost/health >/dev/null; do
            kill -0 $server
            sleep 0.05
          done

          # The prompt OneJev was trained on (qev/prompt.py), and the answer read as qev reads it:
          # the next-token probabilities of the option letters. Prints run, the probability of the
          # "none" line, the probability of the best line, and its command.
          ask() {
            jq -Rs --arg state "$1" '
              [split("\n")[] | select(. != "") | split("\t")[0]] as $d
              | ("ABCDEFGHIJKLMNOPQRSTUVWXYZ" / "")[:$d | length] as $l
              | {
                  prompt: "<|im_start|>system\nApply the question to the state. Choose exactly one of the listed options. Respond with only its uppercase letter, with no explanation or reasoning.<|im_end|>\n<|im_start|>user\n<state>\n\($state)\n</state>\n\nQuestion: Which command is the user asking for?\n\nOptions:\n\([range($d | length) | "\($l[.]). \($d[.])"] | join("\n"))\n\nAnswer with one letter: \($l | join(", ")).<|im_end|>\n<|im_start|>assistant\n<think>\n\n</think>\n\n",
                  n_predict: 1,
                  n_probs: 64,
                  temperature: 0
                }' "$file" |
              curl -sf --unix-socket "$dir/llama.sock" http://localhost/completion -d @- |
              jq -r --rawfile tsv "$file" '
                [$tsv | split("\n")[] | select(. != "") | split("\t")[1]] as $c
                | ("ABCDEFGHIJKLMNOPQRSTUVWXYZ" / "")[:$c | length] as $l
                | [.completion_probabilities[0].top_logprobs[]
                    | {i: (.token as $t | $l | index($t)), p: (.logprob | exp)} | select(.i)]
                | (map(.p) | add) as $sum
                | ((map(select($c[.i] == "false") | .p) | add // 0) / $sum) as $none
                | max_by(.p)
                | [$c[.i] != "false" and $none <= ${voiceNoneMax}, $none, .p / $sum, $c[.i]] | @tsv'
          }

          if [ -n "$tests" ]; then
            ok=0 refused=0 wrong=0
            while IFS=$'\t' read -r phrase want; do
              IFS=$'\t' read -r run none p cmd < <(ask "$phrase")
              [ "$run" = true ] && got=$cmd || got=false
              if [ "$got" = "$want" ]; then
                ok=$((ok + 1))
              elif [ "$got" = false ]; then
                refused=$((refused + 1))
                printf 'refused\t%.2f\t%.2f\t%s\t%s\n' "$none" "$p" "$phrase" "$cmd"
              else
                wrong=$((wrong + 1))
                printf 'wrong\t%.2f\t%.2f\t%s\t%s\n' "$none" "$p" "$phrase" "$cmd"
              fi
            done < "$tests"
            echo "$ok right, $refused refused, $wrong wrong"
            exit
          fi

          while IFS= read -r text; do
            [ -n "$text" ] || continue
            printf 'heard\t%s\n' "$text"
            IFS=$'\t' read -r run _ _ cmd < <(ask "$text") || true
            [ "''${run:-}" != true ] || printf 'run\t%s\n' "$cmd"
          done
        '';
      };

      voice = pkgs.writeShellApplication {
        name = "voice";
        runtimeInputs = [
          pkgs.libnotify
          pkgs.niri
          pkgs.pipewire
          pkgs.procps
          pkgs.sox
          pkgs.wireplumber
          voice-pick
          wav2text
        ];
        text = ''
          pidfile="$XDG_RUNTIME_DIR/voice.pid"
          if [ -f "$pidfile" ] && pkill -P "$(cat "$pidfile")" sox; then
            exit 0
          fi

          case "$(wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2>&1)" in
            *MUTED*) notify-send -u critical "Voice control" "The microphone is muted"; exit 1 ;;
            Volume:*) ;;
            *) notify-send -u critical "Voice control" "No microphone"; exit 1 ;;
          esac

          echo $$ > "$pidfile"
          dir=$(mktemp -d -p "$XDG_RUNTIME_DIR" voice-XXXXXX)
          sox=
          trap 'kill $sox 2>/dev/null || true; rm -rf "$pidfile" "$dir"' EXIT
          sounds=${pkgs.sound-theme-freedesktop}/share/sounds/freedesktop/stereo
          pw-play "$sounds/device-added.oga"

          # One clip per sentence: sox closes clipNNN.wav at each pause and opens the next.
          sox -q -t pulseaudio default -r 16000 -c 1 -b 16 "$dir/clip.wav" \
            silence 1 0.1 1% 1 ${voicePauseSeconds} 1% : newfile : restart &
          sox=$!

          n=1 idle=0
          while kill -0 $sox 2>/dev/null; do
            printf -v clip '%s/clip%03d.wav' "$dir" "$n"
            printf -v next '%s/clip%03d.wav' "$dir" "$((n + 1))"
            if [ -e "$next" ]; then
              # Under 0.2 s is a click or a cough.
              [ "$(stat -c %s "$clip")" -lt 6400 ] || wav2text "$clip" || true
              rm "$clip"
              n=$((n + 1)) idle=0
            elif [ "$idle" -ge $((${voiceIdleSeconds} * 10)) ]; then
              kill $sox
            else
              # ponytail: polls; inotifywait if a tenth of a second ever matters.
              sleep 0.1
              idle=$((idle + 1))
            fi
          done | voice-pick | while IFS=$'\t' read -r kind text; do
            # Through niri: its PATH has noctalia, and a command started like a bind outlives this script.
            case $kind in
              heard) niri msg action spawn -- noctalia msg osd-show hourglass "$text" ;;
              run) niri msg action spawn-sh -- "$text" ;;
            esac
          done
          pw-play "$sounds/device-removed.oga"
        '';
      };
    in
    {
      home.packages = [
        dictate
        listen
        voice
        voice-pick
        wav2text
      ];

      xdg.configFile."voice/commands.tsv".source = ./voice-commands.tsv;
    };
}
