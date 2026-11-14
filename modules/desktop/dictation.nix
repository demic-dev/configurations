{ ... }:
let
  pauseSeconds = "1.5";
  model = {
    url = "https://huggingface.co/handy-computer/moonshine-streaming-medium-gguf/resolve/56302cde2ae162d1357a833d91775bcd06e91e1b/moonshine-streaming-medium-Q8_0.gguf";
    hash = "sha256-98lWQkm1CPYBKSfsT55TYIfaU6cEf4WMqZdb6l91KZ4=";
  };
  voicePauseSeconds = "0.8";
  voiceNoneMax = "0.15";
  voiceModel = {
    url = "https://huggingface.co/mradermacher/OneJev1.6-0.8B-GGUF/resolve/54f205a532e283f1b0697d78891f6968c57c3ebc/OneJev1.6-0.8B.Q8_0.gguf";
    hash = "sha256-EiXE+NkHY2wtRyWuXKM6K6MqZOhO/GoJBSg5eQlws64=";
  };
  # "hey linux" in the pieces of the model's bpe.model: echo "HEY LINUX" | spm_encode --model bpe.model
  wakeWord = "▁HE Y ▁LI N U X";
  wakeBoost = "1.0";
  wakeThreshold = "0.25";
  wakeModel = {
    url = "https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01.tar.bz2";
    hash = "sha256-Jx0DmwZYBPGG7ZLKplqepQPRzCfzq+sj/Cc4sUeaRFk=";
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
      # The same override as modules/services/llama-cpp.nix, so both share one build.
      llama = pkgs.llama-cpp.override { nodejs_latest = pkgs.nodejs_24; };

      voice-pick = pkgs.writeShellApplication {
        name = "voice-pick";
        runtimeInputs = with pkgs; [
          curl
          jq
          libnotify
          llama
          util-linux
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
          if [ -z "$tests" ]; then
            text=$(cat)
            [ -n "$text" ] || exit 1
          fi

          # The model loads in 0.4 s and holds 1.8 GB, so the server only lives for the call.
          dir=$(mktemp -d -p "$XDG_RUNTIME_DIR" voice-XXXXXX)
          taskset -c 4-7 llama-server --host "$dir/llama.sock" -m ${pkgs.fetchurl voiceModel} \
            --threads 4 --ctx-size 2048 --fit off --no-warmup --cache-ram 0 --no-webui >/dev/null 2>&1 &
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

          IFS=$'\t' read -r run _ _ cmd < <(ask "$text") || true
          if [ "''${run:-}" != true ]; then
            notify-send "Voice control" "No command for: $text"
            exit 1
          fi
          echo "$cmd"
        '';
      };

      voice = pkgs.writeShellApplication {
        name = "voice";
        runtimeInputs = [
          listen
          pkgs.niri
          voice-pick
        ];
        text = ''
          text=$(listen ${voicePauseSeconds})
          [ -n "$text" ] || exit 0
          # Shown while the model picks. Through niri, whose PATH has noctalia.
          niri msg action spawn -- noctalia msg osd-show hourglass "$text"
          cmd=$(voice-pick <<< "$text")
          # Through niri and not sh: the command starts like a bind and outlives this script.
          niri msg action spawn-sh -- "$cmd"
        '';
      };
      kws = pkgs.fetchzip wakeModel;

      alsaStdin = pkgs.writeText "asound.conf" ''
        pcm.stdin {
          type file
          slave.pcm { type null }
          file "/dev/null"
          infile "/dev/stdin"
          format "raw"
        }
      '';

      wake = pkgs.writeShellApplication {
        name = "wake";
        runtimeInputs = [
          pkgs.pipewire
          pkgs.sherpa-onnx
          pkgs.systemd
          pkgs.util-linux
          voice
        ];
        text = ''
          pidfile="$XDG_RUNTIME_DIR/listen.pid"
          voice_pid=
          # The spotter only reads ALSA devices, and its own way into PipeWire fails on satie, so pw-record
          # feeds it through an ALSA device that reads stdin. It spins on end of input: when the recorder
          # dies the script goes down with it and systemd restarts both.
          # CPUs 0-3 are the M1's efficiency cores: the spotter has no deadline.
          {
            pw-record --raw --rate 16000 --channels 1 --format s16 -P '{ application.name = wake }' - || true
            kill 0
          } | ALSA_CONFIG_PATH=${alsaStdin} taskset -c 0-3 sherpa-onnx-keyword-spotter-alsa \
            --tokens=${kws}/tokens.txt \
            --encoder=${kws}/encoder-epoch-12-avg-2-chunk-16-left-64.onnx \
            --decoder=${kws}/decoder-epoch-12-avg-2-chunk-16-left-64.onnx \
            --joiner=${kws}/joiner-epoch-12-avg-2-chunk-16-left-64.onnx \
            --num-threads=1 \
            --keywords-file=${pkgs.writeText "keywords.txt" "${wakeWord} :${wakeBoost} #${wakeThreshold}\n"} \
            stdin 2>&1 |
            while read -r line; do
              case "$line" in
                *'"keyword"'*) ;;
                *)
                  echo "$line" >&2
                  continue
                  ;;
              esac
              # voice runs in the background, so a detection during it is read here and dropped, not queued.
              if [ -n "$voice_pid" ] && kill -0 "$voice_pid" 2>/dev/null; then
                continue
              fi
              if [ -f "$pidfile" ] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
                continue
              fi
              # Noctalia's lock screen sets LockedHint. Anything but a plain "no" counts as locked.
              session=$(loginctl show-user "$USER" -p Display --value) || continue
              [ "$(loginctl show-session "$session" -p LockedHint --value)" = no ] || continue
              voice &
              voice_pid=$!
            done
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

      # Without this the spotter keeps Noctalia's microphone indicator lit, and its OSD never shows for a recording.
      programs.noctalia.settings.shell.privacy.mic_filter_regex = "^wake$";

      systemd.user.services.wake = {
        Unit = {
          Description = "Wake word for voice commands";
          PartOf = [ "graphical-session.target" ];
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${wake}/bin/wake";
          Restart = "always";
          RestartSec = 5;
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
}
