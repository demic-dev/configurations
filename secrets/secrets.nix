let
  # Imported directly (not as a module argument) so the plain `agenix` CLI, which does a
  # bare `import ./secrets.nix`, can still evaluate this file.
  env = import ../env.nix { lib = (import <nixpkgs> { }).lib; };

  micheleAtBach = env.userSettings.bach.ssh.michele.value;
  micheleAtSatie = env.userSettings.satie.ssh.michele.value;


  micheles = [ micheleAtBach micheleAtSatie ];

  bachSystem = env.userSettings.bach.ssh.root.value;
  satieSystem = env.userSettings.satie.ssh.root.value;

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

  # SSH private keys, for single-host recovery (see docs/RECOVERY.md).
  # root-at-* are NOT deployed — recovery blobs only — so each is encrypted to the
  # OTHER host, the one that would need to hand it back.
  "root-at-bach.age".publicKeys = [ satieSystem ];
  "root-at-satie.age".publicKeys = [ bachSystem ];

  # michele-at-* ARE deployed on their own host at boot (hence that host's system key);
  # on recovery they come back for free once the host's root key is restored.
  "michele-at-bach.age".publicKeys = [ bachSystem ];
  "michele-at-satie.age".publicKeys = [ satieSystem ];


  # Passphraseless key used ONLY by git-agecrypt to decrypt secrets/sensitive/*.age silently.
  # Deployed to satie's ~/.ssh/git-agecrypt_ed25519; its public key is a recipient in
  # ../git-agecrypt.toml. Encrypted to satie's host key so agenix can decrypt it at boot.
  "git-agecrypt-key.age".publicKeys = [ micheleAtSatie satieSystem ];
}
