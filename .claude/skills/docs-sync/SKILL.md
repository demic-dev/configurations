---
name: docs-sync
description: Bring docs/ up to date with the commits that changed the configuration since docs/ was last touched. Use when Michele says "sync the docs", "update the docs", "are the docs current", or after a batch of commits made without docs edits.
---

# Sync the docs

The rules for writing in `docs/` are in `AGENT.md`, section "Docs". Read them first.

1. Find the commits since `docs/` last changed:
   ```sh
   base=$(git log -1 --format=%H -- docs/)
   git log --oneline "$base"..HEAD -- . ':!docs'
   ```
   If the list is empty, say the docs are current and stop.
2. For each commit, read its diff and decide whether behaviour changed: a value, a service, a port, what's public, a procedure. Pure refactors with an identical drvPath change nothing a reader sees, unless a path that a page cites moved.
3. Find the pages that describe the changed files. Pages cite files as plain paths:
   ```sh
   git diff --name-only "$base"..HEAD -- . ':!docs' | while read f; do rg -l -F "$f" docs/; done | sort -u
   ```
   A commit that adds, removes or changes an alias or function in `modules/dev/fish.nix`, or a script in `scripts/`, always needs `docs/shell.md`, which is also the man page `configurations(7)`. Check its walkthroughs against the changed commands too.
   A change that no page covers yet may need a new page or section. Ask Michele before adding a page, and add it to `docs/SUMMARY.md`.
4. Edit the pages so they describe the configuration as it is now. Add a "Why not" block only if the change was a real design decision (a serious alternative weighed and rejected, see `AGENT.md`) and its reason is known from the commit, the code comments or Michele. Never for implementation details. Don't invent reasons.
5. Build the site to catch broken links: `nix run nixpkgs#mdbook -- build docs -d /tmp/docs-check`.
   If `docs/shell.md` changed, keep it at one sentence per line, then build the man page and lint it (no output means clean):
   ```sh
   man=$(nix build --no-link --print-out-paths .#configurations-man)/share/man/man7/configurations.7
   man -l "$man"
   nix run nixpkgs#mandoc -- -T lint -W warning "$man"
   ```
6. Show Michele the diff. Commit only when asked, as a docs-only commit, never mixed with a refactor.
