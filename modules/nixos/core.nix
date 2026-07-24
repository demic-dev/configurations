{ ... }:
{
  # Baseline every host gets (present and future): nix settings + sudo hardening.
  flake.nixosModules.core = { ... }: {
    nix.settings = {
      trusted-users = [ "root" "@wheel" ];
      experimental-features = [ "nix-command" "flakes" ];
    };

    security.sudo = {
      enable = true;
      execWheelOnly = true;
    };

    nix.optimise = {
      automatic = true;
      dates = [ "04:00" ];
    };

    nix.gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 15d";
      persistent = true;
    };
  };
}
