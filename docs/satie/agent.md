# Agent user on satie

Coding agents run on satie as one user, `agent`, so an agent only reaches the files it's been given. This page covers that user, how access is granted, and how a harness is added (`modules/dev/agent.nix`, `modules/dev/claude.nix`, `modules/dev/opencode.nix`).

## The user

`agent` is a normal user with uid 1001, primary group `agent` (gid 1001), home `/home/agent`, and membership in the group `repos`. Lingering is on, so its user services keep running without a login.

Every harness runs as `agent`, in the same home, so they share one global `AGENTS.md`, one set of skills, one git identity and one history. Files one harness creates, another can edit.

| Harness | Wrapper | Module |
|---|---|---|
| Claude Code | `claude` | `modules/dev/claude.nix` |
| opencode | `opencode` | `modules/dev/opencode.nix` |

michele runs a harness through its wrapper on the `PATH`, which calls `sudo -u agent`. A sudo rule per harness lets michele do that without a password, for that harness's binary only. `TERM` and `COLORTERM` pass through.

`SSH_AUTH_SOCK` doesn't pass through. It would give the agent access to michele's ssh agent, which is Bitwarden.

<details>
<summary>Why not run the agents as michele?</summary>

They would read and write everything michele can: notes, `~/.ssh`, the password manager's data, every repository. A separate user makes access opt-in.

</details>

`agent`'s home-manager config (`modules/dev/agent.nix`) has git, direnv and two global skills under `~/.claude/skills/`: `dev-shell` (`modules/dev/agent/dev-shell/SKILL.md`), which creates a project's dev shell or adds a `MOTD` to it (see `docs/shell.md`), and `agents-file` (see "Global instructions"). opencode reads Claude Code's skill folder too, so one copy serves both.

## Add a harness

A harness is one file under `modules/dev/`, registering `flake.nixosModules.<name>`. Model it on `modules/dev/opencode.nix`:

- a wrapper named after the command, which runs the binary with `sudo -H -u agent --preserve-env=TERM,COLORTERM`
- a sudo rule letting michele run that binary as `agent` with `NOPASSWD` and `SETENV`
- the harness's own settings under `home-manager.users.agent`
- a link to the global file at the path the harness reads

Then add `<name>` after `agent` in `modules/hosts/satie/default.nix`. The file relies on the `agent` aspect for the user, its groups and its home.

## Access

By default the agent reaches nothing in michele's home. Access goes through the group `repos` and ACLs, set up in `modules/dev/agent.nix`. `repos` has the fixed gid 1100 and two members, michele and `agent`.

- `~/repos` is mode 2750, group `repos`, with a default ACL that gives `repos` read and write on everything inside, including files created later. The agent works there.
- `~/nixos` is a symlink to `~/repos/nixos`.
- `~/Nextcloud` gives "other" no access at all, with a default ACL so new files inherit it.

To give the agent another folder, or take it back, use the fish function `agent-allow` (`modules/dev/fish.nix`). It grants to the group `repos`:

```sh
agent-allow ~/Nextcloud/notes          # read and write, including files created later
agent-allow --no-more ~/Nextcloud/notes
```

It also gives `repos` traverse-only access (`x`) on each parent up to the home folder, so the agent can reach the folder without listing what's next to it. An existing, wider entry on a parent is left alone.

The rule for `~/Nextcloud` only touches "other", so the `repos` entries that `agent-allow` adds keep working.

## Git

michele and `agent` get the same git aspect, so the commit identity matches. The email files are agenix secrets owned by michele with group `repos` and mode 0440, which lets the agent read them (`modules/hosts/satie/users.nix`).

The repositories belong to michele, so git and Nix refuse to work in them as another user ("dubious ownership"). `agent`'s git config marks every directory as safe, `*` (`modules/dev/agent.nix`). The narrower `/home/michele/repos/*` works for git but not for Nix, whose libgit2 doesn't support the wildcard. `agent` reaches only what the group `repos` is given, so the wider rule opens nothing more.

## opencode

opencode's global config (`~/.config/opencode/opencode.json` in `agent`'s home) turns off update checks, since Nix owns the version, and session sharing to opencode's servers. It sets no model or provider: the login and the model choice are made by hand, and the credentials stay in `agent`'s home.

## Global instructions

One `AGENTS.md` holds the rules every agent session follows, in any folder: `modules/dev/agent/AGENTS.md`. A folder's own `AGENTS.md` is loaded after it and wins where the two disagree. It's linked into `agent`'s home at the path each harness reads:

| Harness | Link |
|---|---|
| Claude Code | `~/.claude/CLAUDE.md` (`modules/dev/claude.nix`) |
| opencode | `~/.config/opencode/AGENTS.md` (`modules/dev/opencode.nix`) |

The links point at the checkout, `/home/michele/repos/nixos/modules/dev/agent/AGENTS.md`, not at the store, so an edit there applies to the next session without a rebuild. `agent` reads it through the group `repos`.

The skill `agents-file` (`modules/dev/agent/agents-file/SKILL.md`, linked at `~/.claude/skills/agents-file/SKILL.md`) writes a folder's `AGENTS.md` with only what the global file doesn't already say.

Claude Code adds a `Co-Authored-By` trailer to commits and a line to pull requests by default. `/etc/claude-code/managed-settings.json` sets `"attribution": false`, which turns both off (`modules/dev/claude.nix`). Managed settings rank above `~/.claude/settings.json`, which Claude Code writes to itself and so can't be a store link.
