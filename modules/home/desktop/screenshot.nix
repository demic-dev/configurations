{ ... }:
{
  flake.homeModules.screenshot-niri =
    { pkgs, ... }:
    let
      screenshot = pkgs.writeShellApplication {
        name = "screenshot";
        runtimeInputs = with pkgs; [
          niri
          satty
          wl-clipboard
        ];
        text = ''
          outfile="$HOME/Pictures/Screenshots/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"
          mkdir -p "$(dirname "$outfile")"

          raw="''${XDG_RUNTIME_DIR:-/tmp}/screenshot-$$.png"
          trap 'rm -f "$raw"' EXIT

          # Returns when the UI opens, not when the shot lands, and niri emits no event
          # for it, so wait for the PNG to be complete rather than half-written.
          niri msg action screenshot --path "$raw"
          for _ in $(seq 600); do
            tail -c 8 "$raw" 2>/dev/null | grep -qa IEND && break
            sleep 0.2
          done

          # Escape in the UI writes nothing.
          [ -s "$raw" ] || exit 0

          satty --filename "$raw" \
            --output-filename "$outfile" \
            --early-exit \
            --actions-on-enter save-to-clipboard \
            --copy-command wl-copy
        '';
      };
    in
    {
      home.packages = [ screenshot ];
    };
}
