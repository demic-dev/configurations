{ ... }:
{
  # Baseline every host gets (present and future): nix settings + sudo hardening.
  flake.nixosModules.core = { ... }: {
    nix.settings = {
      trusted-users = [ "root" "@wheel" ];
      experimental-features = [ "nix-command" "flakes" ];
      # During a build, below 10 GiB free Nix collects garbage until 30 GiB are free. Generations are left alone: that's `cleanup`.
      min-free = 10 * 1024 * 1024 * 1024;
      max-free = 30 * 1024 * 1024 * 1024;
    };

    security.sudo = {
      enable = true;
      execWheelOnly = true;
    };

    nix.optimise = {
      automatic = true;
      dates = [ "04:00" ];
    };
  };
}
