{ ... }:
{
  # Relies on the repos group and ~/repos ACLs from the claude aspect.
  flake.nixosModules.opencode =
    { pkgs, ... }:
    let
      wrapper = pkgs.writeShellScriptBin "opencode" ''
        exec /run/wrappers/bin/sudo -H -u ai-agent --preserve-env=TERM,COLORTERM \
          ${pkgs.opencode}/bin/opencode "$@"
      '';
    in
    {
      users.groups.ai-agent.gid = 1002;

      users.users.ai-agent = {
        isNormalUser = true;
        uid = 1002;
        group = "ai-agent";
        extraGroups = [ "repos" ];
        packages = [ pkgs.opencode ];
      };

      environment.systemPackages = [ wrapper ];

      # SSH_AUTH_SOCK is deliberately not preserved: it would hand ai-agent the Bitwarden agent.
      security.sudo.extraRules = [
        {
          users = [ "michele" ];
          runAs = "ai-agent";
          commands = [
            {
              command = "${pkgs.opencode}/bin/opencode";
              options = [ "NOPASSWD" "SETENV" ];
            }
          ];
        }
      ];
    };

  flake.homeModules.opencode = {
    programs.opencode = {
      enable = true;
      settings = {
        autoupdate = false;
        share = "disabled";
      };
    };
  };
}
