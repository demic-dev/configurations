# Agent user on satie

Claude Code runs on satie as a separate user, `claude`, so an agent only reaches the files it's been given. This page covers that user and how access is granted (`modules/dev/claude.nix`).

## The user

`claude` is a normal user with uid 1001 and its own home, in the group `repos`. Lingering is on, so its user services keep running without a login. Its home-manager config only has git and direnv.

michele runs it through a `claude` wrapper on the `PATH`, which calls `sudo -u claude`. A sudo rule lets michele do that without a password, for the Claude Code binary only. `TERM` and `COLORTERM` pass through.

`SSH_AUTH_SOCK` doesn't pass through. It would give the agent access to michele's ssh agent, which is Bitwarden.

<details>
<summary>Why not run Claude Code as michele?</summary>

It would read and write everything michele can: notes, `~/.ssh`, the password manager's data, every repository. A separate user makes access opt-in.

</details>

## Access

By default `claude` reaches nothing in michele's home. Access goes through the `repos` group and ACLs:

- `~/repos` is mode 2750, group `repos`, with a default ACL that gives `repos` read and write on everything inside, including files created later. Agents work there.
- `~/nixos` is a symlink to `~/repos/nixos`.
- `~/Nextcloud` gives "other" no access at all, with a default ACL so new files inherit it.

To give the agent another folder, or take it back, use the fish function `claude-allow` (`modules/dev/fish.nix`):

```sh
claude-allow ~/Nextcloud/notes          # read and write, including files created later
claude-allow --no-more ~/Nextcloud/notes
```

It also gives `repos` traverse-only access (`x`) on each parent up to the home folder, so the agent can reach the folder without listing what's next to it. An existing, wider entry on a parent is left alone.

The rule for `~/Nextcloud` only touches "other", so the `repos` entries that `claude-allow` adds keep working.

## Git

Both users get the same git aspect, so the commit identity matches. The email files are agenix secrets owned by michele with group `repos` and mode 0440, which lets `claude` read them (`modules/hosts/satie/users.nix`).
