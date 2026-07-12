{ inputs, ... }:
let
  env = import ../../../env.nix { inherit (inputs.nixpkgs) lib; };
in
{
  flake.homeModules.fish =
    { pkgs, lib, osConfig ? { }, ... }:
    let
      # The host this home config is deployed on. env.nix drives networking.hostName, so looking
      # the name back up in userSettings gives us that host's configPath for free. In standalone
      # home-manager (the liszt container) there is no osConfig at all, so the rebuild helpers
      # that need a configPath are simply omitted.
      host = lib.attrByPath [ "networking" "hostName" ] null osConfig;
      hostSettings = if host != null then env.userSettings.${host} or null else null;
    in
    {
      programs.fish = {
        enable = true;

        shellAliases = {
          ls = "ls --color=auto";
          ll = "ls -alF --color=auto";
          la = "ls -A --color=auto";
        }
        // lib.optionalAttrs (hostSettings != null) {
          # Rebuild the current host from its flake, both discovered from env.nix.
          update = "nixos-rebuild switch --flake ${hostSettings.configPath}#${host} --sudo";
        };

        functions = lib.optionalAttrs (hostSettings != null) {
          # Build locally and deploy to another host: `update-remote <hostname>`.
          # The flake path is this machine's; the target config + ssh host are the argument.
          update-remote = ''
            if test (count $argv) -ne 1
              echo "usage: update-remote <hostname>" >&2
              return 1
            end
            nixos-rebuild switch --flake ${hostSettings.configPath}#$argv[1] --target-host $argv[1] --sudo --ask-elevate-password
          '';
        };

        plugins = [
          { name = "bass"; src = pkgs.fishPlugins.bass.src; }
          { name = "bobthefish"; src = pkgs.fishPlugins.bobthefish.src; }
        ];

        # bobthefish right-prompt tuning: hide the date, show command duration. The color
        # scheme is intentionally left unset so the active theme injects the palette.
        interactiveShellInit = ''
          set -g theme_display_date no
          set -g theme_display_screen yes
          set -g theme_display_cmd_duration yes
        '';
      };
    };
}
