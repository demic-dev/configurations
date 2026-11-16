{ ... }:
{
  # Relies on the agent aspect for the user and its home.
  flake.nixosModules.opencode =
    { pkgs, ... }:
    let
      wrapper = pkgs.writeShellScriptBin "opencode" ''
        exec /run/wrappers/bin/sudo -H -u agent --preserve-env=TERM,COLORTERM \
          ${pkgs.opencode}/bin/opencode "$@"
      '';
    in
    {
      environment.systemPackages = [ wrapper ];

      home-manager.users.agent =
        { config, ... }:
        {
          programs.opencode = {
            enable = true;
            settings = {
              autoupdate = false;
              share = "disabled";
            };
          };

          # Out of store while the wording is tuned: an edit is live in the next session without a rebuild.
          xdg.configFile."opencode/AGENTS.md".source =
            config.lib.file.mkOutOfStoreSymlink "/home/michele/repos/nixos/modules/dev/agent/AGENTS.md";
        };

      # SSH_AUTH_SOCK is deliberately not preserved: it would hand the agent the Bitwarden agent.
      security.sudo.extraRules = [
        {
          users = [ "michele" ];
          runAs = "agent";
          commands = [
            {
              command = "${pkgs.opencode}/bin/opencode";
              options = [ "NOPASSWD" "SETENV" ];
            }
          ];
        }
      ];
    };
}
