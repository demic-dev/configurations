{ ... }:
{
  # Shared git config, identical on every host
  flake.homeModules.git = { osConfig, pkgs, ... }:
    let
      # git-agecrypt's clean/smudge drivers live in .git/config, which is never cloned, so a
      # fresh `git clone` checks out ciphertext until `git-agecrypt init` is run once. There is
      # no post-clone hook, but `git clone` fires post-checkout right after populating the tree.
      # Shipping this hook via init.templateDir makes every new clone auto-register the drivers,
      # pick the decryption identity, and re-checkout to decrypt — no manual steps per clone.
      #
      # Identity: prefer the dedicated PASSPHRASELESS git-agecrypt key (~/.ssh/git-agecrypt_ed25519,
      # deployed by agenix) so the filter decrypts silently. Fall back to ~/.ssh/id_ed25519 for a
      # host that doesn't have the dedicated key yet (e.g. bach still using its login key).
      gitAgecryptPostCheckout = pkgs.writeShellScript "post-checkout" ''
        set -e
        # $3 == 1 => branch checkout (what `git clone` triggers). Skip file checkouts so the
        # `git checkout -- .` below does not re-enter this hook.
        [ "$3" = "1" ] || exit 0
        root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
        [ -f "$root/.gitattributes" ] || exit 0
        grep -q 'filter=git-agecrypt' "$root/.gitattributes" || exit 0
        command -v git-agecrypt >/dev/null 2>&1 || exit 0

        git config --get filter.git-agecrypt.smudge >/dev/null 2>&1 || git-agecrypt init
        if [ -f "$HOME/.ssh/git-agecrypt_ed25519" ]; then
          git config git-agecrypt.config.identity "$HOME/.ssh/git-agecrypt_ed25519"
        elif [ -f "$HOME/.ssh/id_ed25519" ]; then
          git config git-agecrypt.config.identity "$HOME/.ssh/id_ed25519"
        fi
        # Force the now-registered smudge filter to run on the already-checked-out ciphertext.
        git -C "$root" checkout -- . 2>/dev/null || true
      '';

      gitTemplateDir = pkgs.runCommand "git-template-dir" { } ''
        mkdir -p $out/hooks
        cp ${gitAgecryptPostCheckout} $out/hooks/post-checkout
        chmod +x $out/hooks/post-checkout
      '';
    in
    {
      programs.git = {
        enable = true;

        includes = [
          { path = osConfig.age.secrets.git-email.path; }
          { condition = "hasconfig:remote.*.url:git@github.com:*/**"; path = osConfig.age.secrets.noreply-github-email.path; }
          { condition = "hasconfig:remote.*.url:https://github.com/**"; path = osConfig.age.secrets.noreply-github-email.path; }
        ];

        settings = {
          user.name = "demic-dev";

          init.defaultBranch = "main";
          init.templateDir = "${gitTemplateDir}";
          merge.conflictstyle = "diff3";
          diff.colorMoved = "default";
          pull.ff = "only";
          push.autoSetupRemote = true;

          color.ui = true;
        };
      };
    };
}
