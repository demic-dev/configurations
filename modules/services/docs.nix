{ ... }:
{
  flake.nixosModules.docs =
{ pkgs, env, ... }:
let
  internal = env.cloudSettings.internal;
  domain = "${env.cloudSettings.services.docs.subdomain}.${internal}";
  site = pkgs.runCommand "docs" { nativeBuildInputs = [ pkgs.mdbook ]; } ''
    mdbook build --dest-dir $out ${../../docs}
  '';
in
{
  # Nginx
  services.nginx.virtualHosts.${domain} = {
    serverName = domain;

    useACMEHost = internal;
    forceSSL = true;

    root = site;
  };
}
  ;
}
