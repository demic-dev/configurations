{ env, ... }:
let
  satieSSH = env.userSettings.satie.ssh.michele.value;
  bootSSHLocation = env.userSettings.bach.ssh.boot.location;
in
{
  services.zfs.autoScrub = {
    enable = true;
    interval = "*-*-1,15 02:30";
  };

  boot = {
    # No ip= kernel param since the systemd stage-1 initrd migration:
    # networking.interfaces/defaultGateway are translated into the initrd's networkd
    # config (40-enp7s0.network), which takes priority over anything
    # systemd-network-generator would derive from ip=.
    supportedFilesystems = [ "zfs" ];

    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };

    initrd = {
      systemd.enable = true;

      # Systemd stage-1 asks for the ZFS key via systemd-ask-password, so SSH
      # login goes straight to the pending "Enter key for rpool/..." prompt and
      # disconnects once answered; if the prompt never appears (pool import
      # failed), debug from the VNC console emergency shell instead.
      systemd.users.root.shell = "/bin/systemd-tty-ask-password-agent";

      kernelModules = [
        "virtio-pci"
      ];

      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 2222;

          hostKeys = [
            bootSSHLocation
          ];
          authorizedKeys = [
            satieSSH
          ];
        };
      };
    };
  };
}
