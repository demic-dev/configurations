# Disaster recovery

> The point of this file is that at 2 a.m., with both machines gone, you are not
> reconstructing the trust model from memory. Read the model once, then follow the
> runbook for your scenario.

**First fact:** the configuration itself lives on GitHub
(`git@github.com:demic-dev/configurations.git`) and is fully pushed. A total
hardware loss does **not** lose the config — only the *keys* and *data* are at
risk, and those are what this document is about.

---

## 1. The trust model (why the steps are what they are)

Every secret is encrypted to one or more **public** keys; recovering it needs the
matching **private** key. The private keys and who they belong to:

| Key | Private half lives at | Public name in `env.nix` |
|-----|-----------------------|--------------------------|
| bach host key | `/etc/ssh/ssh_host_ed25519_key` (bind-mounted from `/persist`) | `bachSystem` (`bach.ssh.root`) |
| satie host key | `/etc/ssh/ssh_host_ed25519_key` | `satieSystem` (`satie.ssh.root`) |
| michele@bach | `/home/michele/.ssh/id_ed25519` on bach | `micheleAtBach` |
| michele@satie | `/home/michele/.ssh/id_ed25519` on satie | `micheleAtSatie` |
| git-agecrypt (passphraseless) | `/home/michele/.ssh/git-agecrypt_ed25519` on satie | `satie.ssh.git-agecrypt` |
| bach initrd/boot key | `/persist/etc/secrets/initrd/ssh_host_ed25519_key` | `bach.ssh.boot` |

Two independent encryption systems are in play:

- **agenix** (`secrets/*.age`) — decrypted at boot using the host's **own** host
  key as identity (`age.identityPaths` = `services.openssh.hostKeys`). A host can
  only decrypt what it is a recipient of.
- **git-agecrypt** (`secrets/sensitive/*.age`) — decrypted in the working tree by
  a git filter, recipients `micheleAtBach` + the git-agecrypt key. These are read
  **at flake-eval time** via `lib.fileContents` in `env.nix` (bach's IP, gateway,
  subdomains, borg repo URLs, …), so **bach cannot even be built without them
  decrypted.**

agenix recipient groups (`secrets/secrets.nix`):

- `systems = [ bachSystem, satieSystem ]`
- `micheles = [ micheleAtBach, micheleAtSatie ]`
- bach-only secrets (`backup_passphrase`, `immich-backup_passphrase`,
  `nextcloud_root_pass`, `cloudflare_dns_challenge`, `miniflux_admin_pass`,
  `ghost-*`) → `[ bachSystem, micheleAtBach ]`
- satie-only secrets (`michele-password`, `git-agecrypt-key`) → `[ micheleAtSatie, satieSystem ]`
- `git-email`, `noreply-github-email` → `micheles ++ systems`

### Recovery blobs (the cross-host safety net)

Each recovery blob is encrypted to exactly the key that needs it:

- **`root-at-bach` → `satieSystem`**, **`root-at-satie` → `bachSystem`** — a host
  never decrypts its *own* (undeployed) root key, so each is encrypted only to the
  *other* host, which is the one that hands it back during recovery.
- **`michele-at-bach` → `bachSystem`**, **`michele-at-satie` → `satieSystem`** —
  these *are* deployed at boot, so each is encrypted to its own host's system key.
  They are recovered **for free**: restoring a host's root key lets that host
  redeploy its own michele key on the next boot — no separate step.

This is what makes **single-host** recovery possible without the off-machine kit:
the survivor decrypts the dead host's `root-at-*` blob and hands you its key.

Two things to remember about them:

- **`root-at-*` are NOT deployed to disk.** They are recovery material only. Do
  **not** add an `age.secrets.root-at-*` with `path = …ssh_host_ed25519_key` — that
  points agenix at its own identity and bricks the host on the next reboot.
- They are encrypted to `systems` (both **host** keys). If **both** hosts are gone,
  nothing on either machine can decrypt them. That is the total-loss case, and it
  is why the off-machine kit below exists.

---

## 2. The off-machine recovery kit

These must live **outside both machines** (Bitwarden + one offline copy — paper /
encrypted USB). Verify this list is complete periodically; it is the single point
of failure for total loss.

- [ ] **`root@bach` private key** — authorized at BorgBase; this is your entry into
      the backups *and* bach's identity for agenix. (Not in the backup — `/etc/ssh`
      is not a backed-up path — so it can only come from here.)
- [ ] **borg passphrase (generic repo)** — decrypts the main backup.
- [ ] **borg passphrase (immich repo)** — decrypts the immich backup.
- [ ] **both borg repo URLs** — they live in `secrets/sensitive/*.age`, so record
      them here in plaintext too, or you can't address the repos.
- [ ] **bach ZFS pool passphrase** — entered at boot over SSH on port 2222 to
      unlock `rpool`. Needed to unlock the existing pool on any reboot; for a
      from-scratch rebuild you may set a new one.
- [ ] *(recommended)* **git-agecrypt private key** (passphraseless) — lets you
      decrypt `secrets/sensitive/*` and build bach *without* first extracting
      `/home` from the backup. Removes one ordering dependency in total loss.

`root@satie` and the michele keys are **not** required in the kit — they are
recoverable from bach via the `root-at-satie` / `michele-at-*` blobs.

---

## 3. Golden rules

1. A host key is a machine's root of trust. It is restored **out-of-band**, never
   by agenix onto its own path.
2. **Restore a host's key BEFORE `nixos-rebuild`** on that host — otherwise its
   fresh random key matches no recipient and agenix decrypts nothing.
3. **Extract `/home` (or use the kit's git-agecrypt key) before building bach** —
   `env.nix` reads `sensitive/*` at eval time.
4. satie is recovered *through* bach: **bach decrypts satie's key; then satie
   decrypts satie's own secrets.** bach's key never decrypts satie directly.
5. The backup holds **data, not the OS**: reinstall from the flake, then restore
   data. `/etc/ssh` host keys are **not** in the backup.

---

## 4. Runbook A — one host lost, the other alive

### bach died, satie alive

1. Rebuild bach hardware/VM. On satie, decrypt bach's old **root** key — satie is the
   sole recipient of `root-at-bach` via its host key `satieSystem`:
   ```sh
   cd ~/nixos/secrets
   sudo age -d -i /etc/ssh/ssh_host_ed25519_key root-at-bach.age > ssh_host_ed25519_key
   ```
   (You do **not** decrypt `michele-at-bach` here — it's encrypted only to `bachSystem`,
   so the rebuilt bach redeploys michele's key itself once its root key is restored.)
2. Reinstall NixOS on bach from the flake (recreate `rpool` with ZFS encryption,
   unlock via port 2222). Decrypt `sensitive/*` first — the git-agecrypt key is in
   satie's `~/.ssh/git-agecrypt_ed25519`, so build/eval from satie or copy the key.
3. Place the restored `ssh_host_ed25519_key` at `/etc/ssh/ssh_host_ed25519_key`
   (mode 600, root) on bach **before** the first real rebuild.
4. `nixos-rebuild switch --flake .#bach`. bach's identity is now `bachSystem`; all
   bach secrets decrypt.
5. Restore data from borg (see Runbook B, steps on restore).

### satie died, bach alive

1. On bach, decrypt satie's old host key (bach is a recipient via `bachSystem`):
   ```sh
   cd /path/to/nixos/secrets
   sudo age -d -i /etc/ssh/ssh_host_ed25519_key root-at-satie.age > satie_host_key
   ```
2. Install NixOS on the new satie from the flake, then place `satie_host_key` at
   `/etc/ssh/ssh_host_ed25519_key` (mode 600, root) **before** rebuilding.
3. `nixos-rebuild switch --flake .#satie`. satie's identity is now `satieSystem`,
   so it decrypts its own `michele-password`, `git-agecrypt-key`, `michele-at-satie`
   on its own. (bach could not decrypt those two — it only handed satie its key.)

---

## 5. Runbook B — total loss (both hosts gone)

The cross-host blobs are useless here (both host keys are gone). Recover from the
off-machine kit.

1. From the kit: `root@bach` private key, borg passphrases, repo URLs, ZFS
   passphrase.
2. On any machine with `borg`, restore the backups — no NixOS build needed:
   ```sh
   export BORG_RSH="ssh -i /path/to/root_at_bach_key -o IdentitiesOnly=yes"
   export BORG_PASSPHRASE="…generic repo passphrase…"
   borg list   'ssh://…generic-repo-url…'
   borg extract 'ssh://…generic-repo-url…::<archive>'
   # repeat with the immich repo URL + its passphrase
   ```
   This gives you `/home` back — including `~/.ssh/git-agecrypt_ed25519` and
   michele's keys.
3. **Rebuild bach:**
   - Reinstall NixOS, recreate `rpool` (ZFS native encryption; set/enter the
     passphrase; unlock path is port 2222 per `disko/remoteZFSDecrypt.nix`).
   - Configure git-agecrypt with the key (from the kit or the restored `/home`) so
     `secrets/sensitive/*` decrypt in the working tree — otherwise bach builds with
     a garbage IP and never comes up.
   - Place `root@bach` private key at `/etc/ssh/ssh_host_ed25519_key` (600, root).
   - `nixos-rebuild switch --flake .#bach`. bach can now decrypt everything under
     `bachSystem`/`systems`.
   - Restore the extracted data into place (Nextcloud, Postgres, immich, etc.).
4. **Rebuild satie** — now that bach is alive, follow **Runbook A → "satie died,
   bach alive."** bach decrypts `root-at-satie.age`; you install it on the new
   satie; satie decrypts the rest itself.

---

## 6. After any rebuild — housekeeping

- `agenix -r` — re-encrypt every secret to the current recipient set (run after any
  change to `secrets/secrets.nix` or a rekeyed identity).
- Confirm the restored host key matches its recorded public half, e.g. on satie:
  ```sh
  ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key
  # must equal satie.ssh.root.value in env.nix
  ```
- Re-authorize the relevant host key at BorgBase if you generated a new one instead
  of restoring the old.
- Backups are `startAt` 01:00 (generic) / 02:00 (immich); confirm the next run
  succeeds (`systemctl status borgbackup-job-generic`).

---

## 7. What's in the backup (for reference)

Generic job (`modules/nixos/services/backup.nix`), paths: `/home`,
`/persist/data/nextcloud`, `/persist/data/static-files`, `/etc/machine-id`,
`/var/log`, `/var/lib/{acme,calibre-web,postgresql,tailscale}`. Immich has its own
job/repo (`modules/nixos/services/immich.nix`). **Not** backed up: `/etc/ssh` host
keys, the nix store / OS (rebuilt from the flake).
