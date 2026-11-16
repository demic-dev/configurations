---
name: dev-shell
description: Create a project's Nix dev shell (a dev flake, or shell.nix), or update an existing one, and give it a MOTD listing the project's commands. Use when Michele says "add a dev shell", "make a dev flake", "add a MOTD", "update the dev shell", or similar.
---

# Dev shell with a MOTD

On Michele's hosts, fish prints a dev shell's `MOTD` every time direnv loads it, with the project's name and a small λ (function `motd` in `modules/dev/fish.nix` of the NixOS configuration, `/home/michele/repos/nixos`).
`mkShell` attributes become environment variables, so the whole contract is one attribute:

```nix
pkgs.mkShell {
  packages = [ pkgs.typst build ];
  MOTD = ''
    build   compile every PDF into uploads/
  '';
}
```

## Steps

1. Read the project's `AGENTS.md` / `CLAUDE.md` and `README` if present. Their rules win over this skill.
2. Find the commands Michele types in this project: scripts in the flake (`writeShellApplication`, `writeShellScriptBin`), `scripts/`, `justfile`, `Makefile`, `package.json` scripts, `pyproject.toml` scripts, the README's usage section. Check that each one really exists and works from the dev shell.
3. Existing dev shell: add `MOTD` to the `mkShell` that already exists and change nothing else. With several `devShells`, add it to each one that has its own commands. If `flake.nix` imports `shell.nix`, edit `shell.nix`.
4. No dev shell:
   - The project has a `flake.nix`: add `devShells.<system>.default` in the style the flake already uses (plain, flake-utils, flake-parts).
   - It has none: create a `flake.nix` with a `nixpkgs` input and `devShells` for `aarch64-linux` and `x86_64-linux` (`nixpkgs.lib.genAttrs`). Only the packages the project's build files show it needs.
   - `.envrc` with `use flake` (or `use nix` for a `shell.nix`), and `.direnv/` in `.gitignore`.
   - New files must be `git add`ed (paths only, never `git add -A`), or the flake can't see them.
5. Write the `MOTD`:
   - One command per line: the name as typed (with its short argument form, e.g. `build <file>`), then a short lowercase description. Names in one left-aligned column, at least two spaces before the descriptions.
   - Only the project's own commands. No generic tools (`git`, `python`, `cargo build`) unless the project wraps them, and not every package in the shell.
   - A handful of lines. If nothing is worth listing, add no `MOTD` and say so.
6. Verify:
   - `nix flake check` (or `nix-instantiate --eval -A MOTD shell.nix`), and `nix eval --raw .#devShells.<system>.default.MOTD` to see the text.
   - Optionally `direnv allow && direnv exec . printenv MOTD`. If `.envrc` is new, Michele still has to run `direnv allow` once from their own account.
7. Show the diff. Commit only when asked, in the project's commit style. Never push.

## Rules

- Keep it minimal: the attribute and, only if missing, the shell, `.envrc` and `.gitignore` line. No refactors, no new inputs beyond `nixpkgs`, no formatting changes.
- Don't touch files outside the project.
- Never use em dashes, in files or commit messages.
