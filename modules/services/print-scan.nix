{ ... }:
{
  flake.nixosModules.print-scan =
{ config, pkgs, env, ... }:
let
  user = env.userSettings.${config.networking.hostName}.user;
in
{
  services.printing = {
    enable = true;
    drivers = [ pkgs.gutenprint ];   # fallback
  };

  # mDNS: needed for CUPS to find the printer AND helps scanner discovery
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;
  };

  hardware.sane.enable = true;

  # BJNP discovery: 8612 = bjnp, 8610 = mfnp
  networking.firewall.allowedUDPPorts = [ 8610 8612 ];

  users.users.${user}.extraGroups = [ "scanner" "lp" ];

  environment.systemPackages = with pkgs; [ sane-backends simple-scan ];
};
}
