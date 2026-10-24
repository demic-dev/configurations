{ inputs, ... }:
{
  # satie's machine layer: Apple-Silicon (Asahi) boot + hardware scan.
  flake.nixosModules.satie-hardware = { lib, modulesPath, env, ... }: {
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

      # linux-asahi/uboot-asahi are otherwise built from the ambient (unstable)
      # pkgs, so every nixpkgs bump mints a new kernel hash and misses the
      # cachix cache. Upstream's CI builds them against its own pinned nixpkgs;
      # instantiating them from that same pin is what makes them substitutable.
      # Only these two packages read this option, so the rest of satie stays on
      # our nixpkgs.
      # mkForce because the upstream module always defines this to the ambient pkgs.
      pkgs = lib.mkForce (import inputs.nixpkgs-asahi {
        system = "aarch64-linux";
        overlays = [ inputs.nixos-apple-silicon.overlays.default ];
      });
    };

    # After resume the speaker PCM / asahi-audio convolver nodes come back in an error state (EIO/EPERM) and PipeWire
    # never retries them, so no output sink is offered until the session's audio stack is restarted.
    powerManagement.resumeCommands = ''
      systemctl --user -M ${env.userSettings.satie.user}@ restart pipewire pipewire-pulse wireplumber || true
    '';

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
