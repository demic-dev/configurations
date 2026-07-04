let

  micheleAtBach = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMjDuFgmRgyjZ/Ye/QiFetZ6r+W9SGB4ufJcxzCF0ALP";
  micheleAtSatie = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKUnGzmayiQ8SazjVxi8KPAmgJQQssVbSCpAerMn0Eve";


  micheles = [ micheleAtBach micheleAtSatie ];

  bachSystem = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIK7rFUiGulUCjRKMua3OXkAyfnvkZLHwBud4kb37gT83";
  satieSystem = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBjIqDJcBd5/kw+kA8DNdM1KB2IZivH17GrIN+wEiTp5";

  systems = [ bachSystem satieSystem ];
in
{
  "nextcloud_root_pass.age".publicKeys = [
    bachSystem
    micheleAtBach
  ];

  "cloudflare_dns_challenge.age".publicKeys = [
    bachSystem
    micheleAtBach
  ];

  "miniflux_admin_pass.age".publicKeys = [
    bachSystem
    micheleAtBach
  ];

  # Backups
  "backup_passphrase.age".publicKeys = [
    bachSystem
    micheleAtBach
  ];

  "immich-backup_passphrase.age".publicKeys = [
    bachSystem
    micheleAtBach
  ];

  # Ghost's Secrets
  "ghost-storiedisilicio-env.age".publicKeys = [
    micheleAtBach
    bachSystem
  ];
  "ghost-storiedisilicio-db-env.age".publicKeys = [
    micheleAtBach
    bachSystem
  ];

  "git-email.age".publicKeys = micheles ++ systems;

  "noreply-github-email.age".publicKeys = micheles ++ systems;
  
  "michele-password.age".publicKeys = [ micheleAtSatie satieSystem ];
  "michele-at-satie.age".publicKeys = [ micheleAtSatie satieSystem ];

  # Passphraseless key used ONLY by git-agecrypt to decrypt secrets/sensitive/*.age silently.
  # Deployed to satie's ~/.ssh/git-agecrypt_ed25519; its public key is a recipient in
  # ../git-agecrypt.toml. Encrypted to satie's host key so agenix can decrypt it at boot.
  "git-agecrypt-key.age".publicKeys = [ micheleAtSatie satieSystem ];
}
