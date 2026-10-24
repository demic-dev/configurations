{ ... }:
{
  flake.nixosModules.tailscale = {
    services.tailscale.enable = true;

    environment.persistence."/persist".directories = [ "/var/lib/tailscale" ];
  };
}
