{ ... }:
{
  flake.nixosModules.postgresql =
{ config, pkgs, ... }:
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;

    extensions =  with pkgs.postgresql_16.pkgs; [
    pgvector
    vectorchord
  ];
    settings.shared_preload_libraries = [ "vchord.so" "vector.so" ];
  };
  environment.persistence."/persist".directories = [
    "/var/lib/postgresql"
  ];
}
  ;
}
