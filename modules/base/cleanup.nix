{ ... }:
{
  # Instead of nix.gc: nix-collect-garbage keeps generations only by age, this keeps the last 2.
  flake.nixosModules.cleanup =
    { config, pkgs, ... }:
    let
      cleanup = pkgs.writeShellApplication {
        name = "cleanup";
        runtimeInputs = [
          config.nix.package
          pkgs.coreutils
          pkgs.gawk
          pkgs.gnused
        ];
        text = ''
          if [ "$(id -u)" -ne 0 ]; then
            exec sudo "$0"
          fi

          profile=/nix/var/nix/profiles/system

          # Shows a command's output only if it fails, so a clean run prints just the summary.
          run() {
            local out
            out=$("$@" 2>&1) || { printf '%s\n' "$out" >&2; return 1; }
            printf '%s\n' "$out"
          }
          step() {
            if [ -t 2 ]; then echo "$1..." >&2; fi
          }
          free_bytes() {
            df --output=avail -B1 / | tail -n1
          }

          before=$(free_bytes)

          step "deleting old generations"
          removed=$(run nix-env -p "$profile" --delete-generations +2 | sed -n 's/^removing profile version //p' | paste -sd' ')
          kept=$(nix-env -p "$profile" --list-generations | awk '{print $1}' | paste -sd' ')

          step "updating the boot menu"
          # From the profile, not /run/current-system, so a pending `update -m boot` stays the default entry.
          run "$profile/bin/switch-to-configuration" boot >/dev/null

          step "collecting garbage"
          run nix-store --gc >/dev/null

          after=$(free_bytes)
          echo "removed generations ''${removed:-none}"
          echo "kept generations $kept"
          echo "freed $(numfmt --to=iec -- $((after - before))), now $(numfmt --to=iec "$after") free ($(df --output=pcent / | tail -n1 | tr -d ' ') used)"

          dirs=()
          for dir in /var/log/journal /var/cache /var/lib/systemd/coredump /root/.cache /home/*/.cache; do
            if [ -d "$dir" ]; then dirs+=("$dir"); fi
          done
          du -sh "''${dirs[@]}" | sort -rh
        '';
      };
    in
    {
      environment.systemPackages = [ cleanup ];

      systemd.services.cleanup = {
        serviceConfig.Type = "oneshot";
        serviceConfig.ExecStart = "${cleanup}/bin/cleanup";
        startAt = "weekly";
      };
      systemd.timers.cleanup.timerConfig.Persistent = true;
    };
}
