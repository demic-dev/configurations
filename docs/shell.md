# Shell reference

What to type on satie or bach to work with this configuration: the commands it installs, and short walkthroughs for the tasks done from a shell.
The same page is installed on both hosts as the man page `configurations(7)`, built from `docs/shell.md` by `modules/dev/fish.nix`.

## Commands

The aliases and functions come from the fish aspect (`modules/dev/fish.nix`), on both hosts.
The scripts are in `scripts/`.

### update

```sh
update [-b host] [-d host] [-m mode] [nixos-rebuild arguments]
```

Builds and deploys a host with `nixos-rebuild`, from the flake at `configPath` in `env.nix`: `/home/michele/repos/nixos/` on satie, `/home/michele/nixos/` on bach.

| Flag | Default | Meaning |
|---|---|---|
| `-b`, `--build` | this host | host that builds |
| `-d`, `--deploy` | this host | host that switches |
| `-m`, `--mode` | `switch` | `nixos-rebuild` action: `boot`, `test`, `build` and the others |

Other arguments go to `nixos-rebuild` unchanged.
When the target is another host, `update` asks for its sudo password here and passes it over ssh.
Remote builds and deploys use substitutes.

```sh
update                                # build here, switch this host
update -b bach                        # build on bach, switch this host
update -b bach -d bach -m boot        # build on bach, make it bach's next boot
update -m test --show-trace
```

### unlock-bach

```sh
unlock-bach
```

An alias for `ssh root@<bach's IP> -p 2222`: the ssh server in bach's initrd, which only accepts satie's michele key.
The session opens on the "Enter key for rpool" prompt.
After the passphrase it closes and boot continues.

### claude-allow

```sh
claude-allow [--no-more] [path]
```

Gives the `claude` user read and write access to `path` (default: the current directory) through ACLs for the `repos` group, including files created later.
Each parent up to the home folder gets traverse-only access, unless it already has a wider entry.
`--no-more` removes the access to `path` and leaves the parents alone.
It works on satie only, where `modules/dev/claude.nix` creates the `repos` group.

```sh
claude-allow ~/Nextcloud/notes
claude-allow --no-more ~/Nextcloud/notes
```

### share

```sh
share file
share -l | --list
share -d | --delete id
```

Publishes `file` on bach's public static files server at `/<id>/<file name>`, prints the URL, and copies it with `wl-copy` when that's on the `PATH`.
Anyone with the URL can download the file.
`--list` prints the id, file name, size, date and URL of each file published this way.
`--delete` removes one, and accepts only an id (32 hex characters).
Dotfiles are refused.
It runs everything through `ssh bach`.

```sh
share ~/Documents/report.pdf
share --delete 0123456789abcdef0123456789abcdef
```

### ls, ll, la

| Alias | Runs |
|---|---|
| `ls` | `ls --color=auto` |
| `ll` | `ls -alF --color=auto` |
| `la` | `ls -A --color=auto` |

### scripts/add-sensitive.fish

```sh
./scripts/add-sensitive.fish
```

Adds a git-agecrypt value.
It asks for a name, the plain value (end it with Ctrl-D) and the recipients' public keys (an empty line ends the list), registers `secrets/sensitive/<name>.age` in `git-agecrypt.toml` with `git-agecrypt config add`, and stages the file.
The clean filter encrypts it on commit.
It works from anywhere inside the repository.

### scripts/rekey.fish

```sh
./scripts/rekey.fish [public key file]
```

Re-encrypts the agenix secrets whose recipients in `secrets/secrets.nix` include the given ssh public key (default `~/.ssh/id_ed25519.pub`), each to its full recipient set.
The others are skipped, since a plain `agenix --rekey` fails on them.
It works from any directory.

## Walkthroughs

Each one is a handful of commands.
The page named at the end has the reasoning.

### Deploy a host

On satie, from the repository:

```sh
nix flake check              # evaluate both hosts
update -b bach               # satie, built on bach
update -b bach -d bach       # bach
```

What bach can't build within its memory cap, build on satie with plain `update`.
See `docs/deploy.md`.

### Unlock bach after a reboot

```sh
unlock-bach
```

Type the pool's passphrase.
If the prompt never appears, the pool import failed: debug from the VPS provider's VNC console.
See `docs/bach/disk.md`, and `docs/RECOVERY.md` when bach doesn't come back.

### Add or edit a secret

agenix, for values services read at runtime.
A new one also needs an entry with its recipients in `secrets/secrets.nix` and an `age.secrets.<name>.file` line in the module that reads it.

```sh
cd secrets
agenix -e example.age        # create or edit
cd ..
./scripts/rekey.fish         # after changing recipients in secrets/secrets.nix
```

git-agecrypt, for values read at evaluation (domains, IPs).
In satie's checkout the files are plain text, and the clean filter encrypts them on commit.

```sh
./scripts/add-sensitive.fish             # new value
$EDITOR secrets/sensitive/fqdn.age       # existing value
git add secrets/sensitive/fqdn.age
```

See `docs/secrets.md`.

### Give the agent access to a folder

```sh
claude-allow ~/Nextcloud/notes
claude-allow --no-more ~/Nextcloud/notes
```

See `docs/satie/agent.md`.

### Publish a file

```sh
share ~/Documents/report.pdf             # prints the URL and copies it
share --list
share --delete <id>
```

See `docs/bach/network.md`.

### Prove a refactor is a no-op

On satie, before and after the change, with new files `git add`ed:

```sh
nix eval --raw .#nixosConfigurations.bach.config.system.build.toplevel.drvPath; echo
nix eval --raw .#nixosConfigurations.satie.config.system.build.toplevel.drvPath; echo
```

The paths must be identical.
A docs edit changes bach's path, since the docs site is part of it, and an edit to this page changes both, so keep docs out of refactor commits.
See `docs/flake.md`.

### Preview the docs

From the repository, on satie:

```sh
nix run nixpkgs#mdbook -- serve docs
```

Then open `http://localhost:3000`.
A page is only rendered if `docs/SUMMARY.md` lists it.
To read this page as the man page:

```sh
man -l (nix build --no-link --print-out-paths .#configurations-man)/share/man/man7/configurations.7
```

### Debug eduroam

```sh
journalctl -f -u iwd -u NetworkManager   # in one terminal
nmcli connection up eduroam              # in another
```

To change the identity or password, run `agenix -e eduroam.age` from `secrets/`.
See `docs/satie/eduroam.md`.

## See also

The rest of the docs, in `docs/` and on the tailnet: `docs/deploy.md`, `docs/secrets.md`, `docs/flake.md`, `docs/bach/disk.md`, `docs/bach/network.md`, `docs/satie/agent.md`, `docs/satie/eduroam.md`.
For lost hosts and keys, `docs/RECOVERY.md`.
