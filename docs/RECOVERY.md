# Disaster recovery

How to get both machines back after losing one or both. The point of this page is that at 2 a.m., with the machines gone, the trust model doesn't have to be rebuilt from memory. Read the model once, then follow the runbook for the situation.

The configuration itself is on GitHub (`git@github.com:demic-dev/configurations.git`) and fully pushed. Losing all the hardware doesn't lose the config. What's at risk is keys and data, and that's what this page is about.

## Trust model

Every secret is encrypted to one or more public keys, and recovering it needs the matching private key. The private keys:

| Key | Private half lives at | Public name in `env.nix` |
|---|---|---|
| bach host key | `/persist/etc/ssh/ssh_host_ed25519_key`, bind-mounted to `/etc/ssh/` | `bachSystem` (`bach.ssh.root`) |
| satie host key | `/etc/ssh/ssh_host_ed25519_key` | `satieSystem` (`satie.ssh.root`) |
| michele@bach | `/home/michele/.ssh/id_ed25519` on bach | `micheleAtBach` |
| michele@satie | `/home/michele/.ssh/id_ed25519` on satie | `micheleAtSatie` |
| git-agecrypt, passphraseless | `/home/michele/.ssh/git-agecrypt_ed25519` on satie | `satie.ssh.git-agecrypt` |
| bach initrd host key | `/persist/etc/secrets/initrd/ssh_host_ed25519_key` | `bach.ssh.boot` |

Two encryption systems are involved (details in [Secrets](secrets.md)):

- agenix (`secrets/*.age`) decrypts at boot, with the host's own host key as identity. A host can only decrypt what it's a recipient of.
- git-agecrypt (`secrets/sensitive/*.age`) decrypts in the working tree through a git filter, with michele@bach's key or the git-agecrypt key, its two recipients. `env.nix` reads these files at evaluation time (bach's IP, gateway, subdomains, borg repository URLs), so bach can't even be built without them decrypted.

### Recovery files

Two kinds of agenix file exist only for recovery, each encrypted to exactly the key that needs it:

- `root-at-bach` is encrypted to `satieSystem`, and `root-at-satie` to `bachSystem`. A host never decrypts its own root key. The other host does, and hands it back during recovery. These files aren't deployed anywhere.
- `michele-at-bach` is encrypted to `bachSystem`, and `michele-at-satie` to `satieSystem`. These are deployed at boot. Once a host's root key is back, the host redeploys its own michele key at the next boot, with no extra step.

That's what makes losing one host recoverable without the off-machine kit: the survivor decrypts the dead host's `root-at-*` file and hands over its key.

If both hosts are gone, nothing can decrypt the `root-at-*` files. That's the total-loss case, and the reason the kit exists.

> [!WARNING]
> Never add an `age.secrets.root-at-*` entry with its `path` set to the host key. That points agenix at its own identity, and the host decrypts nothing after the next reboot.

## Off-machine kit

These live outside both machines: in Bitwarden, plus one offline copy (paper or an encrypted USB stick). Check now and then that the list is complete. For total loss, it's the single point of failure.

- [ ] The `root@bach` private key (bach's host key). BorgBase authorises it, so it's the way into the backups, and it's bach's identity for agenix. The `generic` archive does contain it, but that archive can only be opened with this key, so the kit is the copy that counts.
- [ ] The borg passphrase of the `generic` repository.
- [ ] The borg passphrase of the `immich` repository.
- [ ] Both borg repository URLs, in plain text. They're in `secrets/sensitive/`, so without a copy here the repositories can't be addressed.
- [ ] bach's ZFS pool passphrase, typed over ssh on port 2222 at boot. Needed to unlock the existing pool. A rebuild from scratch can set a new one.
- [ ] Recommended: the git-agecrypt private key. It decrypts `secrets/sensitive/` directly. Without it, the only other recipient is michele@bach's key, which has to be decrypted from `secrets/michele-at-bach.age` with the `root@bach` key first. The backup doesn't contain either key.

`root@satie` and the michele keys don't need to be in the kit. They come back from bach through `root-at-satie` and `michele-at-*`.

## Rules

1. A host key is a machine's root of trust. It's restored by hand, never by agenix onto its own path.
2. Restore a host's key before the first `nixos-rebuild` on it. Otherwise its new random key matches no recipient, and agenix decrypts nothing.
3. Before building bach, decrypt `secrets/sensitive/`: with the kit's git-agecrypt key, or with michele@bach's key decrypted from `secrets/michele-at-bach.age`.
4. satie is recovered through bach: bach decrypts satie's host key, then satie decrypts its own secrets. bach's key never decrypts satie's secrets directly.
5. The backup holds data, not the OS: reinstall from the flake, then restore data.

## One host lost, the other alive

### bach died, satie alive

1. Get a new VM. On satie, decrypt bach's old host key. satie is the only recipient of `root-at-bach`:
   ```sh
   cd ~/nixos/secrets
   sudo age -d -i /etc/ssh/ssh_host_ed25519_key root-at-bach.age > ssh_host_ed25519_key
   ```
   `michele-at-bach` doesn't need decrypting here. bach redeploys it on its own once its host key is back.
2. Install NixOS on bach from the flake: recreate `rpool` with ZFS encryption and the datasets listed in step 3 of total loss below, unlocked through port 2222, and create a new initrd host key as in that step. Build from satie, where `secrets/sensitive/` is decrypted, or copy satie's `~/.ssh/git-agecrypt_ed25519` to where you build.
3. Before the first real rebuild, put the restored key at `/persist/etc/ssh/ssh_host_ed25519_key` on bach (mode 600, owner root). agenix reads it from `/persist`, before impermanence mounts it on `/etc/ssh`.
4. Run `nixos-rebuild switch --flake .#bach`. bach's identity is `bachSystem` again, and all its secrets decrypt.
5. Restore the data from borg (see [Backups](bach/backups.md)).

### satie died, bach alive

1. On bach, decrypt satie's old host key. bach is the only recipient of `root-at-satie`:
   ```sh
   cd /path/to/nixos/secrets
   sudo age -d -i /etc/ssh/ssh_host_ed25519_key root-at-satie.age > satie_host_key
   ```
2. Install NixOS on the new satie from the flake. Before rebuilding, put `satie_host_key` at `/etc/ssh/ssh_host_ed25519_key` (mode 600, owner root).
3. Run `nixos-rebuild switch --flake .#satie`. satie's identity is `satieSystem` again, so it decrypts `michele-password`, `git-agecrypt-key` and `michele-at-satie` itself. bach couldn't have decrypted those; it only handed satie its key.

## Total loss

Both host keys are gone, so the recovery files are useless. Everything starts from the kit.

1. From the kit, take the `root@bach` key, both borg passphrases, both repository URLs and the ZFS passphrase.
2. On any machine with `borg`, restore the backups. No NixOS build needed:
   ```sh
   export BORG_RSH="ssh -i /path/to/root_at_bach_key -o IdentitiesOnly=yes"
   export BORG_PASSPHRASE="…generic passphrase…"
   borg list 'ssh://…generic repository URL…'
   borg extract 'ssh://…generic repository URL…::<archive>'
   # then the same with the immich URL and passphrase
   ```
   This brings back bach's data, but no key for `secrets/sensitive/`: bach never had the git-agecrypt key, and `~/.ssh/id_ed25519` in the archive is only a symlink into `/run/agenix`. Unless the kit has the git-agecrypt key, decrypt michele@bach's key from a clone of the repository:
   ```sh
   age -d -i /path/to/root_at_bach_key secrets/michele-at-bach.age > michele_at_bach_key
   ```
3. Rebuild bach:
   - Install NixOS and recreate `rpool` with ZFS native encryption (set the passphrase; it's typed on port 2222 at every boot, see `modules/hosts/bach/zfs.nix`) and its datasets: `rpool/local/nix`, `rpool/safe/persist`, `rpool/safe/persist/data`, and `rpool/local/tmp` and `rpool/local/cache` created with `-o mountpoint=legacy`. See [Disk and boot](bach/disk.md).
   - The initrd host key isn't in the backup. Create a new one before installing: installing the bootloader copies it into the initrd as an initrd secret, and fails if the file is missing. From the installer, with the new pool mounted at `/mnt`:
     ```sh
     mkdir -p /mnt/persist/etc/secrets/initrd
     ssh-keygen -t ed25519 -N "" -f /mnt/persist/etc/secrets/initrd/ssh_host_ed25519_key
     ```
     Put its public half in `bach.ssh.boot.value` in `env.nix`.
   - Set up git-agecrypt with the kit's git-agecrypt key or michele@bach's key from step 2 (`git config git-agecrypt.config.identity <key>`, see [Secrets](secrets.md)), so `secrets/sensitive/` decrypts. Otherwise bach builds with a garbage IP and never comes up.
   - Put the `root@bach` key at `/persist/etc/ssh/ssh_host_ed25519_key` (mode 600, owner root).
   - Run `nixos-rebuild switch --flake .#bach`. bach can now decrypt everything encrypted to `bachSystem`.
   - Put the extracted data in place (see [Backups](bach/backups.md)).
4. Rebuild satie with "satie died, bach alive" above.

## After any rebuild

- After any change to `secrets/secrets.nix` or to an identity, re-encrypt the secrets to their current recipients with `./scripts/rekey.fish`. It rekeys only the secrets the given key can decrypt (see [Secrets](secrets.md)).
- Check that a restored host key matches its public half, for example on satie:
  ```sh
  ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key    # must equal satie.ssh.root.value in env.nix
  ```
- If a host got a new key instead of the old one, authorise it at BorgBase.
- After a new initrd key, satie's `known_hosts` entry for bach on port 2222 no longer matches. Remove it with `ssh-keygen -R '[<bach's IP>]:2222'`.
- The backups start at 01:00 (`generic`) and 02:00 (`immich`). Check that the next run succeeds: `systemctl status borgbackup-job-generic`.

What each backup contains, and what it leaves out, is in [Backups](bach/backups.md).
