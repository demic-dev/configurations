{ config, libs, pkgs, env, ... }:
let
  rootSSH = env.userSettings.bach.ssh.root.location;
in
{
  environment.persistence."/persist" = {
    hideMounts = true;
    files = [
      "/etc/machine-id"
      rootSSH
    ];

    directories = [
      "/var/log"
      "/home"
    ];
  };
}
