{ ... }:
{
  # Shared git config, identical on every host
  flake.homeModules.git = { osConfig ? { }, pkgs, lib, ... }:
    let
      # git-agecrypt's clean/smudge drivers live in .git/config, which is never cloned, so a fresh `git clone` checks out ciphertext until `git-agecrypt init` is run once. There is no post-clone hook, but `git clone` fires post-checkout right after populating the tree. Shipping this hook via init.templateDir makes every new clone auto-register the drivers, pick the decryption identity, and re-checkout to decrypt — no manual steps per clone.
      gitAgecryptPostCheckout = ./agecrypt.postcheckout.sh;

      gitTemplateDir = pkgs.runCommand "git-template-dir" { } ''
        mkdir -p $out/hooks
        cp ${gitAgecryptPostCheckout} $out/hooks/post-checkout
        chmod +x $out/hooks/post-checkout
      '';
    in
    {
      programs.git = {
        enable = true;

        # agenix-backed email routing only exists when home-manager runs inside NixOS
        includes = lib.optionals (osConfig ? age) [
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
