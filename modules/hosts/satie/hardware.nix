{ ... }:
{
  # satie's machine layer: Apple-Silicon (Asahi) boot + hardware scan.
  flake.nixosModules.satie-hardware = { lib, modulesPath, env, ... }: {
    imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.systemd-boot.graceful = true;

    boot.tmp.cleanOnBoot = true;

    boot.kernel.sysctl."vm.mmap_rnd_bits" = 31;

    boot.kernelParams = [ "brcmfmac.roamoff=1" ];

    boot.initrd.availableKernelModules = [ "usb_storage" ];

    hardware.asahi = {
      enable = true;
      peripheralFirmwareDirectory = ./firmware;
    };

    # After resume the speaker PCM / asahi-audio convolver nodes come back in an error state (EIO/EPERM) and PipeWire
    # never retries them, so no output sink is offered until the session's audio stack is restarted.
    powerManagement.resumeCommands = ''
      systemctl --user -M ${env.userSettings.satie.user}@ restart pipewire pipewire-pulse wireplumber || true
    '';

    # The daemon panics when the speaker codec isn't ready yet (ENXIO), and the stock 10 retries in 1 s run out
    # before it is. Only the udev rule starts it, so once it gives up the speakers stay muted until reboot.
    systemd.services.speakersafetyd = {
      unitConfig.StartLimitIntervalSec = 0;
      serviceConfig.RestartSec = 5;
    };

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    boot.extraModprobeConfig = ''
      options hid_apple iso_layout=0
    '';

    fileSystems."/" = {
      device = "/dev/disk/by-uuid/d3c75759-b5ce-41fc-8e58-2f7e39fa4be9";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/B97F-190E";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

    zramSwap.enable = true;

    swapDevices = [{
      device = "/var/lib/swapfile";
      size = 10 * 1024;
    }];

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    system.stateVersion = "25.11";
  };
}
