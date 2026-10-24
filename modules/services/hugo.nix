{ ... }:
{
  flake.nixosModules.hugo =
{ pkgs, env, ... }:
let
  fqdn = env.cloudSettings.fqdn;
  webRoot = "/var/www/${fqdn}";
  githubUri = "demic-dev/website";
  filesRoot = "/data/static-files";

  # Download cv with my name already on it for smoother organization
  staticFilesLocations = {
    "= /resume" = {
      alias = "${filesRoot}/resume.pdf";
      extraConfig = ''
        add_header Content-Disposition 'inline; filename="michele-de-cillis-cv.pdf"';
      '';
    };
    "= /resume-ats" = {
      alias = "${filesRoot}/resume-ATS.pdf";
      extraConfig = ''
        add_header Content-Disposition 'inline; filename="michele-de-cillis-cv-ATS.pdf"';
      '';
    };
  };
in
{
  systemd.services.${fqdn} = {
    enable = true;
    description = ''
      https://${fqdn} source
    '';
    serviceConfig = {
      Type = "oneshot";
    };
    path = [ pkgs.nix ];
    startAt = "*:0/5";
    script = ''
      set -ex

      nix build github:${githubUri} --out-link ${webRoot} --extra-experimental-features nix-command --extra-experimental-features flakes --refresh --no-write-lock-file
    '';
  };

  # Nginx
  services.nginx.virtualHosts = {
    ${fqdn} = {
      serverName = fqdn;

      useACMEHost = fqdn;
      forceSSL = true;

      root = webRoot;

      locations = staticFilesLocations;
    };
    "www.${fqdn}" = {
      serverName = "www.${fqdn}";

      enableACME = false;
      useACMEHost = fqdn;
      forceSSL = true;

      root = webRoot;

      locations = staticFilesLocations;
    };
  };
}
  ;
}
