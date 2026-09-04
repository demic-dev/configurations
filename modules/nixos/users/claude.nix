{ ... }:
{
  flake.nixosModules.claude =
    { pkgs, ... }:
    let
      wrapper = pkgs.writeShellScriptBin "claude" ''
        exec /run/wrappers/bin/sudo -H -u claude --preserve-env=TERM,COLORTERM \
          ${pkgs.claude-code}/bin/claude "$@"
      '';
    in
    {
      users.groups.repos = { };
      users.groups.claude.gid = 1001;

      users.users.claude = {
        isNormalUser = true;
        uid = 1001;
        group = "claude";
        extraGroups = [ "repos" ];
        linger = true;
        packages = [ pkgs.claude-code ];
      };

      users.users.michele.extraGroups = [ "repos" ];

      environment.systemPackages = [ wrapper ];

      # SSH_AUTH_SOCK is deliberately not preserved: it would hand claude the Bitwarden agent.
      security.sudo.extraRules = [
        {
          users = [ "michele" ];
          runAs = "claude";
          commands = [
            {
              command = "${pkgs.claude-code}/bin/claude";
              options = [ "NOPASSWD" "SETENV" ];
            }
          ];
        }
      ];

      systemd.tmpfiles.rules = [
        "d /home/michele/repos 2755 michele repos -"
        "a+ /home/michele/repos - - - - g:repos:rwX,d:g:repos:rwX"
        "L+ /home/michele/nixos - - - - /home/michele/repos/nixos"
      ];
    };
}
