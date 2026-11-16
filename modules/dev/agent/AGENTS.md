# AGENTS.md

These rules apply in every folder on this machine. A folder's own `AGENTS.md` adds to them, and wins where the two disagree.

## Where to look first

- The folder's `AGENTS.md`, then its `README` and `docs/`. Answer from what is already written down before asking.
- `man configurations`: the shell commands, aliases and walkthroughs of this system.
- `/home/michele/nixos`: the NixOS flake that configures every host, with its docs in `docs/`.
- The hosts run NixOS. A missing tool comes from the project's dev shell or from `nix shell nixpkgs#<name>`, never from a global install.

## Replies

- Lead with the answer. Write for the person reading, not as a log of what you did.
- Talk like a colleague at a whiteboard: plain words, short sentences, technical terms where they are the right words. No filler, no praise, no selling.
- Short by default. A list only when the content is a list, a table only to compare things.
- Say what you don't know, and mark a guess as a guess. Never invent a name, a flag, an API or a version: check it, or ask.
- Report honestly: what you ran and what it printed, what you only read, what you could not verify.
- Text meant to be copied (a command, a message, a draft) goes in a code block or a plain paragraph, never in a blockquote.
- Never use em dashes, anywhere: replies, files, commits. Use a comma, a colon, parentheses or a full stop.

## Code

- Write the simplest thing that solves what was asked. Nothing for a need that doesn't exist yet: no interface with one implementation, no helper with one caller, no setting for a value that never changes, no guard for a case that can't happen.
- Reuse before writing: the standard library, the dependencies already there, the upstream option. A new dependency needs a reason worth its cost. If rewriting something that exists seems necessary, stop and ask.
- Stay inside the task. Don't widen it into nearby features or a refactor, and keep existing behaviour unless the task changes it.
- Match the file you are in: its naming, its idioms, its layout.
- Plain names. A constant carries its unit (`TIMEOUT_MS`). Return early instead of nesting.
- Follow the UNIX philosophy: one job per program, programs that compose through text, files and exit codes, logic apart from interface, mechanism apart from policy. Silent on success. On failure, a message on stderr and a non-zero exit code.
- Efficient means fast for the machine. After writing, ask once whether it can be simpler or quicker.
- No dead code: nothing commented out, no unused names, no debug output.

### Comments

A comment says only what the code can't:

- a measured number, and where it comes from
- how an upstream library or tool really behaves, or the bug being worked around, with its issue number
- a constraint the next reader would otherwise break
- why the obvious way is wrong here

A doc line on a file, a function or a constant is welcome when it carries such a fact. Never restate the code, narrate a change or leave a `TODO`. If a comment is needed to explain what the code does, rewrite the code.

### Tests

Changed behaviour gets a test where the project has tests. Name a test as a sentence about behaviour: `empty_input_returns_no_rows`. Never weaken a lint, delete a test or add an exception only to get a green run.

## Docs

- Describe the thing as it is now. History belongs in git.
- Plain words, short declarative sentences, present tense. A guide speaks to the reader as "you" and gives its steps in the imperative.
- Say what something means before saying what to do about it.
- A heading is what the reader sees or wants to do: "Restore a file", "What won't help".
- Be exact: the real value, the real label, the real error message, the path of the file that sets it. Link a claim to its source.
- Say plainly what doesn't work and what can't be done.
- Describe, don't sell. No adjectives that praise.
- Keep guides (how to do a thing) apart from reference (the rules a part of the system follows).
- A change in behaviour updates the docs in the same change.

## Commits

One line and nothing else: no body, no footers, no `Co-Authored-By`, no mention of AI.

```
<type>[(scope)][!]: <description>
```

The rules of Conventional Commits 1.0.0, as used here:

- The type is a noun. `feat` adds a feature, `fix` fixes a bug. The others in use: `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `style`, `chore`, `revert`.
- The scope is optional: a noun in parentheses naming the part touched, as in `fix(parser): ...`.
- A colon and a space follow, then the description: a short summary of the change.
- A breaking change puts `!` before the colon, and the description says what breaks: `feat(api)!: drop the v1 endpoints`.
- Lowercase, imperative, no full stop, 72 characters at most.
- One topic per commit. Each commit builds and passes the checks on its own.

Adapted from conventionalcommits.org (CC BY 3.0).

## Working habits

- In a code repo, work in a git worktree on a branch of its own, never in the user's checkout: the user works there at the same time. When the user approves the change, commit it in the worktree, rebase it on `main` if `main` has moved, merge it into `main` fast-forward, and remove the worktree and the branch.
- Unless the folder's file says otherwise: commit only on that approval, and never push, deploy or rebuild a system on your own.
- Instructions for agents live in a file named `AGENTS.md`, whichever harness you are. Never create a `CLAUDE.md`, a `GEMINI.md`, a `.cursorrules` or any other harness's own file. A rule the user asks you to keep for a folder goes into that folder's `AGENTS.md`.
- Files change under you, because the user edits by hand while you work. Read a file again before editing it, make small edits, and never put back something that was removed. Leave uncommitted work that isn't yours alone.
- Done means: the project's own checks ran and passed, the docs match the change, and the reply says what was verified and what wasn't.
