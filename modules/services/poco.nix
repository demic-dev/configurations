{ ... }:
{
  flake.nixosModules.poco =
{ config, inputs, env, ... }:
let
  domain = "${env.cloudSettings.services.nextcloud.subdomain}.${env.cloudSettings.internal}";
in
{
  imports = [ inputs.poco.nixosModules.hosting ];

  services.poco = {
    enable = true;
    url = "https://${domain}/remote.php/dav/files/micheledecillis/notes/";
    user = "micheledecillis";
    passwordFile = config.age.secrets.poco_app_pass.path;
    eventsDir = "/data/nextcloud/data/micheledecillis/files/notes/_events";
  };

  # Agenix
  age.secrets.poco_app_pass.file = ../../secrets/poco_app_pass.age;

  # Persistence
  environment.persistence."/persist".directories = [
    {
      directory = "/var/lib/private/poco";
      mode = "0700";
    }
  ];
}
  ;
}
