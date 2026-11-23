{ ... }:
{
  flake.nixosModules.tailnet-server = {
    services.tailscale = {
      openFirewall = true;
      # Not just dropping "--ssh": `tailscale set` changes only the flags it gets, and the
      # prefs persist in /var/lib/tailscale, so Tailscale SSH would stay on and keep port 22.
      extraSetFlags = [ "--ssh=false" ];
    };
  };
}
