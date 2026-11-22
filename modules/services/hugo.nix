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
      StateDirectory = "website";
    };
    path = [ pkgs.nix pkgs.git ];
    startAt = "*:0/5";
    script = ''
      set -e

      rev=$(git ls-remote https://github.com/${githubUri} HEAD)
      rev=''${rev%%[[:space:]]*}
      if [ "$rev" = "$(cat "$STATE_DIRECTORY/rev" 2>/dev/null)" ] && [ -e ${webRoot} ]; then
        exit 0
      fi

      nix build github:${githubUri}/$rev --out-link ${webRoot} --extra-experimental-features nix-command --extra-experimental-features flakes --no-write-lock-file
      echo "$rev" > "$STATE_DIRECTORY/rev"
    '';
  };

  # Nginx
  services.nginx.virtualHosts = {
    ${fqdn} = {
      serverName = fqdn;

      useACMEHost = fqdn;
      forceSSL = true;

      extraConfig = ''
        allow all;
        ssl_verify_client on;
      '';

      root = webRoot;

      locations = staticFilesLocations;
    };
    "www.${fqdn}" = {
      serverName = "www.${fqdn}";

      enableACME = false;
      useACMEHost = fqdn;
      forceSSL = true;

      extraConfig = ''
        allow all;
        ssl_verify_client on;
      '';

      root = webRoot;

      locations = staticFilesLocations;
    };
  };
}
  ;
}
