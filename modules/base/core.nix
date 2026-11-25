{ ... }:
{
  # Baseline every host gets (present and future): nix settings + sudo hardening.
  flake.nixosModules.core = { ... }: {
    nix.settings = {
      trusted-users = [ "root" "@wheel" ];
      experimental-features = [ "nix-command" "flakes" ];
      # On every host because bach builds satie: without it the Asahi kernel gets compiled.
      substituters = [ "https://nixos-apple-silicon.cachix.org" ];
      trusted-public-keys = [ "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20=" ];
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
