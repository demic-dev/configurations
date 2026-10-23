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

          # Unlock bach's ZFS pool from its initrd SSH (see disko/remoteZFSDecrypt.nix)
          unlock-bach = "ssh root@${env.userSettings.bach.network.ip.v4} -p 2222";
        };

        functions = {
          # `update [--build host] [--deploy host] [--mode switch|boot|test|…] [nixos-rebuild args]`; defaults: this host, switch.
          update = ''
            argparse -i 'b/build=' 'd/deploy=' 'm/mode=' -- $argv
            or return 1
            set -l deploy ${host}
            set -q _flag_deploy; and set deploy $_flag_deploy
            set -l mode switch
            set -q _flag_mode; and set mode $_flag_mode

            set -l args $mode --flake ${configPath}#$deploy
            if set -q _flag_build; and test $_flag_build != ${host}
              set -a args --build-host $_flag_build
            end
            if test $deploy = ${host}
              set -a args --sudo
            else
              # sudo on the target has no terminal to prompt on, so the password is asked here and piped over ssh.
              set -a args --target-host $deploy --ask-sudo-password
            end
            contains -- --build-host $args; or contains -- --target-host $args; and set -a args --use-substitutes

            nixos-rebuild $args $argv
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
              # Traverse-only on the parents (never downgrading an existing entry), so claude reaches $dir without listing them.
              set -l p (dirname $dir)
              while string match -q "$HOME/*" $p
                getfacl -cp $p | string match -q 'group:repos:*'
                or setfacl -m g:repos:x $p
                set p (dirname $p)
              end
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
