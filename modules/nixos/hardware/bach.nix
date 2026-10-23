{ ... }:
{
  # bach's machine layer: nixos-generate-config hardware scan + the ZFS/impermanence
  # wiring it depends on (remote unlock in initrd + the /persist bind mounts).
  flake.nixosModules.bach-hardware = { config, lib, pkgs, modulesPath, ... }: {
    imports = [
      (modulesPath + "/profiles/qemu-guest.nix")
      # disko/ lives at the repo root (outside ./modules so import-tree ignores it);
      # pulled in here so the aspect carries bach's whole machine layer.
      ../../../disko/remoteZFSDecrypt.nix
      ../../../disko/persistence.nix
    ];

    boot.initrd.availableKernelModules = [ "xhci_pci" "virtio_scsi" "sr_mod" ];
    boot.kernelModules = [ ];
    boot.extraModulePackages = [ ];

    boot.zfs.devNodes = "/dev/disk/by-uuid";
    boot.kernelParams = [ "zfs.zfs_arc_max=1073741824" ];
    # Single dedicated VM, no shared storage another host could import this pool from,
    # so the double-import risk forceImportRoot=false guards against doesn't apply here.
    # Keeping it true so an OOM-triggered hard reboot recovers on its own instead of
    # needing a VNC console trip to add zfs_force=1 at the bootloader.
    boot.zfs.forceImportRoot = true;

    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
      options = [ "mode=755" ];
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/4879-77EA";
      fsType = "vfat";
    };

    fileSystems."/nix" = {
      device = "rpool/local/nix";
      fsType = "zfs";
      options = [ "zfsutil" ];
    };

    fileSystems."/persist" = {
      device = "rpool/safe/persist";
      fsType = "zfs";
      options = [ "zfsutil" ];
      neededForBoot = true;
    };

    fileSystems."/persist/data" = {
      device = "rpool/safe/persist/data";
      fsType = "zfs";
      options = [ "zfsutil" ];
      neededForBoot = true;
    };

    # nofail drops the ordering before local-fs.target; put it back so nothing writes into the tmpfs underneath.
    fileSystems."/tmp" = {
      device = "rpool/local/tmp";
      fsType = "zfs";
      options = [ "nofail" "x-systemd.before=local-fs.target" ];
    };

    fileSystems."/var/cache" = {
      device = "rpool/local/cache";
      fsType = "zfs";
      options = [ "nofail" "x-systemd.before=local-fs.target" ];
    };

    boot.tmp.cleanOnBoot = true;

    # Swap on a zvol needs memory to write out, exactly when there's none left.
    zramSwap.enable = true;

    nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
  };
}
