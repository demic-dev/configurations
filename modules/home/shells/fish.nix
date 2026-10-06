{ inputs, ... }:
let
  env = import ../../../env.nix { inherit (inputs.nixpkgs) lib; };
in
{
  flake.homeModules.fish =
    { pkgs, osConfig, ... }:
    let
      # The host this home config is deployed on. env.nix drives networking.hostName, so looking the name back up in userSettings gives us that host's configPath for free.
      host = osConfig.networking.hostName;
      inherit (env.userSettings.${host}) configPath;
    in
    {
      programs.fish = {
        enable = true;

        shellAliases = {
          ls = "ls --color=auto";
          ll = "ls -alF --color=auto";
          la = "ls -A --color=auto";

          # Rebuild the current host from its flake
          update = "nixos-rebuild switch --flake ${configPath}#${host} --sudo";
        };

        functions = {
          # Build locally and deploy to another host: `update-remote <hostname>`
          update-remote = ''
            if test (count $argv) -ne 1
              echo "usage: update-remote <hostname>" >&2
              return 1
            end
            nixos-rebuild switch --flake ${configPath}#$argv[1] --target-host $argv[1] --sudo --ask-elevate-password
          '';

          # Give the claude user rw access to a folder (default: cwd), including files created later: `claude-allow [--no-more] [path]`
          claude-allow = ''
            argparse no-more -- $argv
            or return 1
            set -l dir (realpath (string length -q -- $argv[1]; and echo $argv[1]; or echo .))
            or return 1
            if set -q _flag_no_more
              setfacl -R -x g:repos,d:g:repos $dir
              and echo "claude can no longer access $dir"
            else
              setfacl -R -m g:repos:rwX,d:g:repos:rwX $dir
              and echo "claude can now access $dir"
            end
          '';
        };

        plugins = [
          { name = "bass"; src = pkgs.fishPlugins.bass.src; }
          { name = "bobthefish"; src = pkgs.fishPlugins.bobthefish.src; }
        ];

        # bobthefish tuning
        interactiveShellInit = ''
          set -g theme_display_date no
          set -g theme_display_screen yes
          set -g theme_display_cmd_duration yes
        '';
      };
    };
}
