# Sensitive values (git-agecrypt)

Files here are **committed encrypted** (age) but read as **cleartext from the working tree** at
Nix eval time (see `../../env.nix`). Encryption/decryption happens through a git clean/smudge
filter provided by [git-agecrypt](https://github.com/vlaci/git-agecrypt).

## How it actually works (important mental model)

- **Recipients** (who can decrypt each file) are listed in `../../git-agecrypt.toml`.
- The **filter drivers live in `.git/config`**, which is *per-clone and never cloned*. A fresh
  clone therefore checks out ciphertext until `git-agecrypt init` has been run in it.
- The **decryption identity** is a single ssh key set via `git-agecrypt.config.identity` in
  `.git/config`. We use a **dedicated passphraseless key** `~/.ssh/git-agecrypt_ed25519`
  (deployed by agenix) so the filter never prompts. The login key `~/.ssh/id_ed25519` is
  passphrase-protected and must **not** be used here — it makes every git command prompt.
- git-agecrypt only re-encrypts a file when its **plaintext changes**. Changing the recipient
  list alone does **not** re-encrypt existing files (see "rotate recipients" below).

The home-manager git module (`../../modules/home/git.nix`) ships an `init.templateDir`
`post-checkout` hook that auto-runs `git-agecrypt init`, sets the identity, and decrypts — so a
fresh clone Just Works, provided the identity key is present.

## Add a new sensitive value

```bash
# file must exist first (write the cleartext value into it)
printf 'the-value' > secrets/sensitive/NAME.age
# register it for the current recipients (repeat -r per recipient)
git-agecrypt config add \
  -r "ssh-ed25519 …michele@bach" \
  -r "ssh-ed25519 …git-agecrypt@michele" \
  -p secrets/sensitive/NAME.age
git add secrets/sensitive/NAME.age   # clean filter encrypts the committed blob
```

## After a fresh clone / re-clone

If the template hook is deployed, cloning already handled this. Otherwise, or to redo it manually:

```bash
git-agecrypt init                                                    # register filter drivers
git config git-agecrypt.config.identity ~/.ssh/git-agecrypt_ed25519  # passphraseless identity
git checkout -- secrets/sensitive/                                   # smudge -> decrypt working tree
```

## Add a NEW host

Because every host uses the **same** passphraseless `git-agecrypt@michele` key, adding a host needs
**no re-encryption**:

1. Deploy the git-agecrypt private key to the new host at `~/.ssh/git-agecrypt_ed25519`
   (add an `age.secrets.git-agecrypt-key` block like satie's, and a rule in `../secrets.nix`).
2. Clone the repo there. The template hook (or the manual steps above) initialises it.

Only if you want a host to decrypt with its **own** distinct key do you need to add that key as a
recipient and rotate (next section).

## Rotate / add a recipient key (forces re-encryption)

Adding a key to `git-agecrypt.toml` does **not** touch existing ciphertext — git-agecrypt reuses
the blob from git HEAD whenever the plaintext is unchanged. To actually re-encrypt to a new
recipient set, run this **on a host that can already decrypt** (so cleartext is available):

```bash
# 0. add the new recipient to git-agecrypt.toml (all files) and commit that first
git-agecrypt init
git config git-agecrypt.config.identity ~/.ssh/git-agecrypt_ed25519   # or a key that can decrypt
git checkout -- secrets/sensitive/                                     # cleartext working tree
head -c 25 secrets/sensitive/fqdn.age; echo                           # sanity: real value, not "age-…"

BASE=$(git rev-parse HEAD)
tmp=$(mktemp -d); cp secrets/sensitive/*.age "$tmp/"

git rm -q secrets/sensitive/*.age && git commit -qm "temp: drop"       # remove from HEAD…
cp "$tmp"/*.age secrets/sensitive/ && rm -rf .git/git-agecrypt         # …so there's no blob to reuse
git add secrets/sensitive/*.age && git commit -qm "temp: re-add"       # fresh encrypt to all recipients

git reset --soft "$BASE" && git commit -m "re-encrypt sensitive secrets"   # collapse temp commits
rm -rf "$tmp"
git push
```

The two temporary commits are collapsed away by the `reset --soft`, so only one clean commit (the
re-encrypted blobs) is pushed.

## If git gets "stuck" prompting for a passphrase

That means the filter is registered but the configured identity is passphrase-protected (or can't
decrypt). Un-break it by removing the filter registration:

```bash
git config --remove-section filter.git-agecrypt
git config --remove-section diff.git-agecrypt
```

Note: `git-agecrypt deinit` is **buggy** (it targets a mistyped `fiter.git-agecrypt` section and
leaves the filter in place) — use the two commands above instead.

Reference: <https://github.com/vlaci/git-agecrypt>
