# Agent users on satie

Coding agents run on satie as separate users, so an agent only reaches the files it's been given. This page covers those users and how access is granted (`modules/dev/claude.nix`, `modules/dev/opencode.nix`).

## The users

| Agent | User | uid | Wrapper | Lingering |
|---|---|---|---|---|
| Claude Code | `claude` | 1001 | `claude` | on |
| opencode | `ai-agent` | 1002 | `opencode` | off |

Each is a normal user with its own home and group, in the group `repos`. With lingering on, `claude`'s user services keep running without a login. Their home-manager config has git and direnv, plus opencode's own config for `ai-agent` and, for `claude`, the global skill `dev-shell` (`modules/dev/agent/dev-shell/SKILL.md`), which creates a project's dev shell or adds a `MOTD` to it (see `docs/shell.md`), and `agents-file` (see "Global instructions").

michele runs each agent through a wrapper on the `PATH`, which calls `sudo -u <user>`. A sudo rule per agent lets michele do that without a password, for that agent's binary only. `TERM` and `COLORTERM` pass through.

`SSH_AUTH_SOCK` doesn't pass through. It would give the agent access to michele's ssh agent, which is Bitwarden.

<details>
<summary>Why not run the agents as michele?</summary>

They would read and write everything michele can: notes, `~/.ssh`, the password manager's data, every repository. A separate user makes access opt-in.

</details>

## Access

By default an agent reaches nothing in michele's home. Access goes through the `repos` group and ACLs, set up in `modules/dev/claude.nix` and shared by both agents:

- `~/repos` is mode 2750, group `repos`, with a default ACL that gives `repos` read and write on everything inside, including files created later. Agents work there.
- `~/nixos` is a symlink to `~/repos/nixos`.
- `~/Nextcloud` gives "other" no access at all, with a default ACL so new files inherit it.

To give the agents another folder, or take it back, use the fish function `claude-allow` (`modules/dev/fish.nix`). It grants to the `repos` group, so both agents get the same access:

```sh
claude-allow ~/Nextcloud/notes          # read and write, including files created later
claude-allow --no-more ~/Nextcloud/notes
```

It also gives `repos` traverse-only access (`x`) on each parent up to the home folder, so the agents can reach the folder without listing what's next to it. An existing, wider entry on a parent is left alone.

The rule for `~/Nextcloud` only touches "other", so the `repos` entries that `claude-allow` adds keep working.

## Git

All users get the same git aspect, so the commit identity matches. The email files are agenix secrets owned by michele with group `repos` and mode 0440, which lets the agents read them (`modules/hosts/satie/users.nix`).

The repositories belong to michele, so git and Nix refuse to work in them as another user ("dubious ownership"). `ai-agent`'s git config marks every directory as safe, `*` (`modules/hosts/satie/users.nix`). The narrower `/home/michele/repos/*` works for git but not for Nix, whose libgit2 doesn't support the wildcard. `ai-agent` reaches only what the `repos` group is given, so the wider rule opens nothing more.

## opencode

opencode's global config (`~/.config/opencode/opencode.json` in `ai-agent`'s home) turns off update checks, since Nix owns the version, and session sharing to opencode's servers. It sets no model or provider: the login and the model choice are made by hand, and the credentials stay in `ai-agent`'s home.

## Global instructions

One `AGENTS.md` holds the rules every agent session follows, in any folder: `modules/dev/agent/AGENTS.md`. A folder's own `AGENTS.md` is loaded after it and wins where the two disagree. It's linked into each agent's home, at the path its harness reads:

| Harness | User | Link |
|---|---|---|
| Claude Code | `claude` | `~/.claude/CLAUDE.md` (`modules/dev/claude.nix`) |
| opencode | `ai-agent` | `~/.config/opencode/AGENTS.md` (`modules/dev/opencode.nix`) |

The links point at the checkout, `/home/michele/repos/nixos/modules/dev/agent/AGENTS.md`, not at the store, so an edit there applies to the next session without a rebuild. Both users read it through the `repos` group.

The skill `agents-file` (`modules/dev/agent/agents-file/SKILL.md`, linked for `claude` at `~/.claude/skills/agents-file/SKILL.md`) writes a folder's `AGENTS.md` with only what the global file doesn't already say.

Claude Code adds a `Co-Authored-By` trailer to commits and a line to pull requests by default. `/etc/claude-code/managed-settings.json` sets `"attribution": false`, which turns both off (`modules/dev/claude.nix`). Managed settings rank above `~/.claude/settings.json`, which Claude Code writes to itself and so can't be a store link.
