{ ... }:
{
  flake.nixosModules.static-files =
{ pkgs, env, ... }:
let
  fqdn = env.cloudSettings.fqdn;
  domain = "${env.cloudSettings.services.static-files.subdomain}.${fqdn}";
  filesRoot = "/data/static-files";
  cvGithubUri = "demic-dev/cv";
in
{
  # Fetch the latest built resume from the cv repo and publish it.
  # Copied (not symlinked) into place so it stays subject to the same
  # disable_symlinks/try_files hardening as everything else being served.
  systemd.services.cv-resume = {
    description = "Fetch and publish resume PDF into static files";
    path = [ pkgs.nix ];
    startAt = "*:0/2";
    environment.HOME = "/var/lib/static-files";
    serviceConfig = {
      Type = "oneshot";
      User = "static-files";
      Group = "static-files";
      StateDirectory = "static-files";
    };
    script = ''
      set -ex

      out=$(nix build github:${cvGithubUri} --no-link --print-out-paths --extra-experimental-features nix-command --extra-experimental-features flakes --refresh --no-write-lock-file)
      install -m 0640 "$out/resume.pdf" ${filesRoot}/resume.pdf
      install -m 0640 "$out/resume-ATS.pdf" ${filesRoot}/resume-ATS.pdf
    '';
  };

  # Nginx
  services.nginx.virtualHosts.${domain} = {
    serverName = domain;

    enableACME = false;
    useACMEHost = fqdn;
    forceSSL = true;

    root = filesRoot;

    # Dotfiles (.htaccess, .git, ...).
    locations."~ /\\." = {
      extraConfig = ''
        deny all;
        return 404;
      '';
    };

    locations."/" = {
      extraConfig = ''
        autoindex off;
        # Nothing outside ${filesRoot} can be reached even if a link is dropped into it.
        disable_symlinks on;
        # Only regular files, no fallbacks.
        try_files $uri =404;
      '';
    };
  };

  # Persistence
  environment.persistence."/persist".directories = [
    {
      directory = filesRoot;
      user = "static-files";
      group = "static-files";
      # Group-writable + setgid so files dropped in by group members
      # stay readable by nginx via the static-files group.
      mode = "2770";
    }
  ];

  # Dedicated owner for the content; nginx only gets group (read) access.
  users.users.static-files = {
    isSystemUser = true;
    group = "static-files";
    uid = 990;
  };
  users.groups.static-files = {
    gid = 990;
    members = [ env.userSettings.bach.user ];
  };

  users.users.nginx.extraGroups = [ "static-files" ];
}
  ;
}
