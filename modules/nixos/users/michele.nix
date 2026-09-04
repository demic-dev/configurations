{ ... }:
{
  # The parts of the `michele` user that are identical on every host.
  flake.nixosModules.michele = { pkgs, ... }: {
    users.users.michele = {
      isNormalUser = true;
      uid = 1000;
      shell = pkgs.fish;
      extraGroups = [ "wheel" "networkmanager" ];

      homeMode = "711";
    };
  };
}
