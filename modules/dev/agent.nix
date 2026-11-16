{ config, ... }:
let
  hm = config.flake.homeModules;
in
{
  flake.nixosModules.agent =
    { ... }:
    {
      # Fixed so it matches on bach, where 981 is taken.
      users.groups.repos.gid = 1100;
      users.groups.agent.gid = 1001;

      users.users.agent = {
        isNormalUser = true;
        uid = 1001;
        group = "agent";
        extraGroups = [ "repos" ];
        linger = true;
      };

      users.users.michele.extraGroups = [ "repos" ];

      home-manager.users.agent = { ... }: {
        home.username = "agent";
        home.homeDirectory = "/home/agent";

        imports = with hm; [ git ];

        programs.direnv = {
          enable = true;
          enableBashIntegration = true;
          nix-direnv.enable = true;
        };

        # The repos belong to michele, so git and Nix refuse them as "dubious ownership" otherwise.
        # "*" and not "/home/michele/repos/*": Nix's libgit2 ignores the path wildcard.
        programs.git.settings.safe.directory = "*";

        # opencode reads Claude Code's skill folder too.
        home.file.".claude/skills/dev-shell/SKILL.md".source = ./agent/dev-shell/SKILL.md;
        home.file.".claude/skills/agents-file/SKILL.md".source = ./agent/agents-file/SKILL.md;

        home.stateVersion = "26.05";
      };

      systemd.tmpfiles.rules = [
        "d /home/michele/repos 2750 michele repos -"
        "a+ /home/michele/repos - - - - g:repos:rwX,d:g:repos:rwX"
        "L+ /home/michele/nixos - - - - /home/michele/repos/nixos"
        # Only "other" is touched, so the repos entries agent-allow adds stay effective.
        "a+ /home/michele/Nextcloud - - - - other::---,default:other::---"
      ];
    };
}
