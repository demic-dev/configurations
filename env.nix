{ lib }:
{
  cloudSettings = {
    email = lib.fileContents ./secrets/sensitive/email.age;
    fqdn = lib.fileContents ./secrets/sensitive/fqdn.age;
    internal = lib.fileContents ./secrets/sensitive/internal.age;
    services = {
      nextcloud = {
        subdomain = lib.fileContents ./secrets/sensitive/nextcloud-subdomain.age;
        port = 8443; # redisPort = port + 1;
        maxUploadSize = "8G";
        client_max_body_size = "8000M";
      };
      immich = {
        borg-repository = lib.fileContents ./secrets/sensitive/immich-borg-repository.age;
        subdomain = lib.fileContents ./secrets/sensitive/immich-subdomain.age;
        port = 2283; # redisPort = port + 1;
      };
      miniflux = {
        subdomain = "rss";
        port = 5401;
      };
      calibre = {
        subdomain = "calibre";
        port = 10291;
      };
      static-files = {
        subdomain = "files";
      };
    };
  };

  userSettings = {
    satie = {
      ssh = {
        michele = {
          value = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKUnGzmayiQ8SazjVxi8KPAmgJQQssVbSCpAerMn0Eve michele@satie";
          location = "/home/michele/.ssh/id_ed25519";
        };
        git-agecrypt = {
          value = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILybbzqNCmNotFldfobNebniei51OEG/EW8obXzODK1k git-agecrypt@michele";
          location = "/home/michele/.ssh/git-agecrypt_ed25519";
        };
        root = {
          value = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBjIqDJcBd5/kw+kA8DNdM1KB2IZivH17GrIN+wEiTp5 root@satie";
          location = "/etc/ssh/ssh_host_ed25519_key";
        };
      };

      id = "3e042fee";

      configPath = "/home/michele/nixos/";

      user = "michele";
      host = "satie";

      home = {
        path = "/home/michele/";
      };

      network = {
        nameservers = [ "1.1.1.1" ];
      };
    };

    bach = {
      ssh = {
        michele = {
          value = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMjDuFgmRgyjZ/Ye/QiFetZ6r+W9SGB4ufJcxzCF0ALP michele@bach";
          location = "/home/michele/.ssh/id_ed25519";
        };
        root = {
          value = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK7rFUiGulUCjRKMua3OXkAyfnvkZLHwBud4kb37gT83 root@bach";
          location = "/etc/ssh/ssh_host_ed25519_key";
        };
        # Separate keypair from the running system's host key above. This one is
        # baked into the initramfs, which lives unencrypted on the boot
        # partition, so anyone with physical access could extract it. Keeping it
        # distinct means a leak of the boot key can't impersonate the real
        # booted host, and known_hosts can tell the two apart (port 2222 vs 22).
        boot = {
          value = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILABPYXIQigaMv47W7vWV86QqrpXsV56ZjvPRhM5i9ss root@nixos";
          location = "/persist/etc/secrets/initrd/ssh_host_ed25519_key";
        };
      };

      borg-repository = lib.fileContents ./secrets/sensitive/backup-borgbase-repository.age;
      
      id = "05835d97";

      configPath = "/home/michele/nixos/";
      
      user = "michele";
      host = "bach";
      
      home = {
        path = "/home/michele/";
      };

      network = {
        ip = {
          v4 = lib.fileContents ./secrets/sensitive/bach-ipv4.age;
          v6 = lib.fileContents ./secrets/sensitive/bach-ipv6.age;
        };
        gateway = lib.fileContents ./secrets/sensitive/bach-gateway.age;
        subnetMask = "255.255.252.0";
        nameservers = [ "1.1.1.1" ];
      };
    };
  };
}

