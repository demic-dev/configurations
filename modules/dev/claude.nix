{ ... }:
{
  # Relies on the agent aspect for the user and its home.
  flake.nixosModules.claude =
    { pkgs, ... }:
    let
      wrapper = pkgs.writeShellScriptBin "claude" ''
        exec /run/wrappers/bin/sudo -H -u agent --preserve-env=TERM,COLORTERM \
          ${pkgs.claude-code}/bin/claude "$@"
      '';
    in
    {
      users.users.agent.packages = [ pkgs.claude-code ];

      environment.systemPackages = [ wrapper ];

      home-manager.users.agent =
        { config, ... }:
        {
          # Out of store while the wording is tuned: an edit is live in the next session without a rebuild.
          home.file.".claude/CLAUDE.md".source =
            config.lib.file.mkOutOfStoreSymlink "/home/michele/repos/nixos/modules/dev/agent/AGENTS.md";
        };

      environment.etc."claude-code/managed-settings.json".text = builtins.toJSON { attribution = false; };

      # SSH_AUTH_SOCK is deliberately not preserved: it would hand the agent the Bitwarden agent.
      security.sudo.extraRules = [
        {
          users = [ "michele" ];
          runAs = "agent";
          commands = [
            {
              command = "${pkgs.claude-code}/bin/claude";
              options = [ "NOPASSWD" "SETENV" ];
            }
          ];
        }
      ];
    };
}
