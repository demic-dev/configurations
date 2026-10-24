{ ... }:
{
  flake.nixosModules.tailnet-server = {
    services.tailscale = {
      openFirewall = true;
      # tailscaled's own SSH server answers port 22 on the tailnet; the tailnet ACL decides who gets in.
      extraSetFlags = [ "--ssh" ];
    };
  };
}
