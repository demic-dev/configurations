{ ... }:
{
  flake.nixosModules.eduroam =
    { config, ... }:
    {
      age.secrets.eduroam.file = ../../secrets/eduroam.age;

      networking.networkmanager.ensureProfiles = {
        environmentFiles = [ config.age.secrets.eduroam.path ];

        profiles.eduroam = {
          connection = {
            id = "eduroam";
            type = "wifi";
          };
          wifi = {
            ssid = "eduroam";
            mode = "infrastructure";
          };
          wifi-security.key-mgmt = "wpa-eap";
          "802-1x" = {
            eap = "peap";
            phase2-auth = "mschapv2";
            identity = "$EDUROAM_ID";
            password = "$EDUROAM_PASSWORD";
            ca-cert = "${./eduroam-unimi-ca.pem}";
            domain-match = "eduroam.unimi.it";
          };
        };
      };
    };
}
