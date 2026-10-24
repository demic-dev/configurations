{ ... }:
{
  flake.nixosModules.ssh =
{ config, pkgs, env, ... }:
let
  rootSSH = env.userSettings.${config.networking.hostName}.ssh.root.location;
in
{
  services.openssh = {
    enable = true;

    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      X11Forwarding = false;
    };

    openFirewall = false;
    startWhenNeeded = false;
    allowSFTP = false;

    extraConfig = ''
      AllowTcpForwarding yes
      AllowAgentForwarding no
      AllowStreamLocalForwarding no
      PermitEmptyPasswords no
    '';

    hostKeys = [
      {
        path = rootSSH;
        type = "ed25519";
      }
    ];
  };

  users.users.sshd.uid = 993;
  users.groups.sshd.gid = 993;
}
  ;
}
