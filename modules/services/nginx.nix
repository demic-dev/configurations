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

    # Tailnet only. Public vhosts opt in with `allow all; ssl_verify_client on;`, so only Cloudflare reaches them
    # (shared origin-pull CA, expires 2029-11-01). Any allow/deny in a block replaces this whole list.
    commonHttpConfig = ''
      allow 100.64.0.0/10;
      allow fd7a:115c:a1e0::/48;
      allow 127.0.0.1;
      allow ::1;
      deny all;
      ssl_client_certificate ${./cloudflare-origin-pull-ca.pem};
    '';

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
