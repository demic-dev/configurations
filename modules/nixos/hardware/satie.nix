{ ... }:
{
  # satie's machine layer: Apple-Silicon (Asahi) boot + hardware scan.
  # Shared nix.settings / nix.gc live in core.nix + optimization.nix (both hosts import them).
  flake.nixosModules.satie-hardware = { lib, modulesPath, ... }: {
    imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = false;
    boot.loader.systemd-boot.graceful = true;

    boot.kernel.sysctl."vm.mmap_rnd_bits" = 31;

    boot.kernelParams = [
      "brcmfmac.feature_disable=0x82000"
      "brcmfmac.roamoff=1"
    ];

    boot.initrd.availableKernelModules = [ "usb_storage" ];

    hardware.asahi = {
      enable = true;
      peripheralFirmwareDirectory = ./firmware;
    };

    hardware.bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    boot.extraModprobeConfig = ''
      options hid_apple iso_layout=0
    '';

    # Apple-Silicon binary cache (kernel/uboot are otherwise built locally).
    nix.settings = {
      substituters = [ "https://nixos-apple-silicon.cachix.org" ];
      trusted-public-keys = [ "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20=" ];
    };

    fileSystems."/" = {
      device = "/dev/disk/by-uuid/d3c75759-b5ce-41fc-8e58-2f7e39fa4be9";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/B97F-190E";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

    swapDevices = [{
      device = "/var/lib/swapfile";
      size = 16 * 1024;
    }];

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

    system.stateVersion = "25.11";
  };
}
