{ inputs, ... }:
{
  flake.nixosModules.impermanence = {
    imports = [ inputs.impermanence.nixosModules.impermanence ];

    environment.persistence."/persist".hideMounts = true;
  };
}
