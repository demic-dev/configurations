{ ... }:
{
  flake.nixosModules.nginx =
{ config, libs, pkgs, env, ... }:
{
  services.nginx = {
    enable = true;

    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    # Otherwise nginx answers unknown hosts with the first vhost alphabetically.
    virtualHosts."_" = {
      default = true;
      rejectSSL = true;
      locations."/".return = "444";
    };
  };
  
  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
  ;
}
