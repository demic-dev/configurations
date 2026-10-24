# Secrets

The flake uses two encryption tools for two kinds of secret. agenix handles secrets that services read at runtime. git-agecrypt handles values the configuration itself needs at evaluation time.

| | agenix | git-agecrypt |
|---|---|---|
| Files | `secrets/*.age` | `secrets/sensitive/*.age` |
| Examples | passwords, API tokens, borg passphrases | domains, bach's IP and gateway, borg repo URLs, the Tailscale policy |
| Decrypted | at activation, on the host, into `/run/agenix/` | in the working tree, by a git filter |
| Decrypted with | the host's ssh host key | a dedicated key on satie |
| Recipients in | `secrets/secrets.nix` | `git-agecrypt.toml` |

The repository is public. Both kinds are committed as ciphertext.

## agenix

Each secret is encrypted to a list of public keys in `secrets/secrets.nix`. At activation, agenix decrypts the secrets a host needs using that host's ssh host key (`age.identityPaths`), so a host can only read secrets it's a recipient of. Evaluation never sees their contents.

The recipient groups:

| Secrets | Recipients |
|---|---|
| bach's services (borg, Nextcloud, OnlyOffice, Miniflux, Cloudflare DNS token) | bach's host key, michele@bach |
| satie only (`michele-password`, `git-agecrypt-key`, `eduroam`) | satie's host key, michele@satie |
| git emails | both host keys, both michele keys |
| `root-at-bach` | satie's host key |
| `root-at-satie` | bach's host key |
| `michele-at-bach`, `michele-at-satie` | their own host's key |

The `root-at-*` files are copies of each host's private host key, encrypted to the other host. They aren't deployed anywhere. They let the surviving host hand back the dead one's key during [disaster recovery](RECOVERY.md).

> [!WARNING]
> Never add an `age.secrets.root-at-*` entry with its `path` set to the host key. That points agenix at its own identity, and the host can no longer decrypt anything after the next reboot.

On bach, `age.identityPaths` points at `/persist/etc/ssh/ssh_host_ed25519_key`, not `/etc/ssh/`. agenix runs in the initrd, a few seconds before impermanence bind-mounts the key into `/etc/ssh`.

### Add an agenix secret

1. In `secrets/secrets.nix`, add an entry with its recipients:
   ```nix
   "example.age".publicKeys = [ bachSystem micheleAtBach ];
   ```
2. From `secrets/`, create it and type the value:
   ```sh
   agenix -e example.age
   ```
3. Declare it in the module that uses it, and read it from its path:
   ```nix
   age.secrets.example.file = ../../secrets/example.age;
   # config.age.secrets.example.path
   ```

### Rekey

After changing recipients in `secrets/secrets.nix`, re-encrypt:

```sh
./scripts/rekey.fish [path/to/ssh_public_key]
```

A plain `agenix --rekey` fails on any secret the current key can't decrypt. The script only rekeys the secrets that list the given key (default `~/.ssh/id_ed25519.pub`), each to its full recipient set.

## git-agecrypt

`env.nix` reads some values with `lib.fileContents ./secrets/sensitive/<name>.age`. On GitHub those files are ciphertext. In satie's working tree, git-agecrypt's smudge filter has decrypted them, so evaluation reads the plain value. When a file is committed, the clean filter encrypts it again.

This has consequences:

- bach can't even be evaluated without the decrypted files. Evaluate on satie.
- The filter is registered in `.git/config`, which isn't cloned. A fresh clone checks out ciphertext until `git-agecrypt init` runs in it. The git aspect (`modules/dev/git/default.nix`) ships a `post-checkout` hook through `init.templateDir` that does this on every clone, provided the key is present.
- The filter decrypts with `~/.ssh/git-agecrypt_ed25519`, a passphraseless key that agenix deploys on satie. The login key has a passphrase, and using it would make every git command prompt.
- git-agecrypt only re-encrypts a file when its plain content changes. Changing the recipients alone leaves existing ciphertext as it is.

<details>
<summary>Why not agenix for these values too?</summary>

agenix decrypts at activation, on the host. These values are needed earlier, while Nix evaluates the configuration: the IP goes into the network config, the domains into nginx and ACME. Only something that decrypts before evaluation works here.

</details>

### Add a sensitive value

```sh
printf 'the-value' > secrets/sensitive/NAME.age
git-agecrypt config add -r "<michele@bach public key>" -r "<git-agecrypt public key>" -p secrets/sensitive/NAME.age
git add secrets/sensitive/NAME.age
```

The public keys are the two listed for every file in `git-agecrypt.toml`. Then read it in `env.nix` with `lib.fileContents`.

### Set up a fresh clone by hand

If the template hook didn't run:

```sh
git-agecrypt init
git config git-agecrypt.config.identity ~/.ssh/git-agecrypt_ed25519
git checkout -- secrets/sensitive/
```

### Re-encrypt to a new recipient set

Because git-agecrypt reuses the committed blob while the plain content is unchanged, re-encrypting means removing the files from HEAD first. Commit the new recipients in `git-agecrypt.toml`, then on a host that can decrypt:

```sh
git-agecrypt init
git config git-agecrypt.config.identity ~/.ssh/git-agecrypt_ed25519
git checkout -- secrets/sensitive/
head -c 25 secrets/sensitive/fqdn.age; echo     # must be the real value, not "age-…"

BASE=$(git rev-parse HEAD)
tmp=$(mktemp -d); cp secrets/sensitive/*.age "$tmp/"
git rm -q secrets/sensitive/*.age && git commit -qm "temp: drop"
cp "$tmp"/*.age secrets/sensitive/ && rm -rf .git/git-agecrypt
git add secrets/sensitive/*.age && git commit -qm "temp: re-add"
git reset --soft "$BASE" && git commit -m "re-encrypt sensitive secrets"
rm -rf "$tmp"
git push
```

The `reset --soft` folds the two temporary commits into one, so only the re-encrypted files get pushed.

### Give another host access

Every host that should decrypt uses the same git-agecrypt key, so no re-encryption is needed. Deploy the key to the new host with an `age.secrets.git-agecrypt-key` block like satie's (`modules/hosts/satie/users.nix`) and a rule in `secrets/secrets.nix`, then clone.

### If git keeps asking for a passphrase

The filter is registered, but the configured identity has a passphrase or can't decrypt. Remove the registration:

```sh
git config --remove-section filter.git-agecrypt
git config --remove-section diff.git-agecrypt
```

Don't use `git-agecrypt deinit`: it targets a misspelled section (`fiter.git-agecrypt`) and leaves the filter in place.
