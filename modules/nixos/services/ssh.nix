{ ... }:
{
  flake.nixosModules.ssh =
{ config, pkgs, ... }:

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
        bits = 4096;
        path = "/persist/etc/ssh/ssh_host_rsa_key";
        type = "rsa";
      }
      {
        path = "/persist/etc/ssh/ssh_host_ed25519_key";
        type = "ed25519";
      }
    ];
  };

  users.users.sshd.uid = 993;
  users.groups.sshd.gid = 993;
}
  ;
}
