---
name: agents-file
description: Write or update a folder's AGENTS.md from what Michele says about the folder, holding only what is local to it, because the global AGENTS.md already applies everywhere. Use when Michele says "add an agents file", "create AGENTS.md", "update the agents file", or similar.
---

# A folder's AGENTS.md

On Michele's hosts a global `AGENTS.md` is loaded in every session (source: `/home/michele/repos/nixos/modules/dev/agent/AGENTS.md`). A folder's own `AGENTS.md` adds what is true only there, and wins where the two disagree. So the folder's file is lean: it never repeats the global one.

## Steps

1. Read the global file, to know what not to repeat.
2. Read what the folder already has: `AGENTS.md`, `CLAUDE.md`, `README`, `docs/`, and the build files (`flake.nix`, `package.json`, `Makefile`, `justfile`, CI workflows).
3. Take Michele's instructions for this folder. Write them with his meaning, not softened and not expanded. An instruction that contradicts the global file is a local rule: write it down, it wins here. Ask only for what you can't find and can't write without.
4. Write `AGENTS.md`, with only the sections that have something to say:
   - An opening line or two: what this folder is.
   - **Where things are**: the layout a newcomer can't guess, and pointers of the form "read X before changing Y".
   - **Checks**: the exact commands that verify a change, ready to copy, with real paths and no placeholders. Run each one, or find it in the build files, before writing it down.
   - **How to work here**: what the agent may do without asking (edit, branch, commit, merge, push, deploy), and the branch rules.
   - **Local rules**: whatever adds to the global file or differs from it (a recap at the end of replies, a spelling, another voice for the docs).
5. Leave out: anything the global file says, anything a look at the tree shows (file listings), history, and in a public repo any name of a person, hostname or secret.
6. An existing `AGENTS.md` is edited in place with small edits. Keep Michele's wording, and never put back something that was removed.
7. Don't create a `CLAUDE.md`. If the folder, or a folder above it, has a `CLAUDE.md` that isn't a link to `AGENTS.md`, say so: Claude Code then reads that file and skips `AGENTS.md`.
8. Show the file, or the diff.
9. Then ask once: "Should this file stand on its own, for people who don't have the global file?" On yes, append the global file's sections on code, comments, tests, docs and commits, word for word, under `## House rules`. Leave out "Where to look first" and "Working habits", which are about this machine.
10. Commit only when asked, in the project's commit style. Never push.

## Rules

- Keep it short, around 40 lines without the house rules. Every line costs context in every session.
- A rule carries its reason in the same sentence when the reason isn't obvious.
- Don't touch other files in the folder.
- Never use em dashes, in the file or in commit messages.
