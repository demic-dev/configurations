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
          config.systemd.package
          pkgs.coreutils
        ];
        text = ''
          if [ "$(id -u)" -ne 0 ]; then
            exec sudo "$0"
          fi

          df -h /
          nix-env -p /nix/var/nix/profiles/system --delete-generations +2
          # Drops the deleted generations from the boot menu. From the profile, not /run/current-system,
          # so a pending `update -m boot` stays the default entry.
          /nix/var/nix/profiles/system/bin/switch-to-configuration boot
          nix-store --gc --quiet
          df -h /

          journalctl --disk-usage
          for dir in /var/cache /var/lib/systemd/coredump /root/.cache /home/*/.cache; do
            if [ -d "$dir" ]; then
              du -sh "$dir"
            fi
          done
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
