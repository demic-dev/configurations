{ inputs, ... }:
let
  env = import ../../env.nix { inherit (inputs.nixpkgs) lib; };
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

          # Unlock bach's ZFS pool from its initrd SSH (see hosts/bach/zfs.nix)
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

          # Publish a file on bach's static files under a random id: `share <file>`, `share --list`, `share --delete <id>`
          share = ''
            argparse l/list 'd/delete=' -- $argv
            or return 1
            set -l root /data/static-files
            set -l url https://${env.cloudSettings.services.static-files.subdomain}.${env.cloudSettings.fqdn}
            if set -q _flag_list
              ssh bach "find $root -mindepth 2 -maxdepth 2 -type f -regextype posix-extended -regex '$root/[0-9a-f]{32}/.*' -printf '%TY-%Tm-%Td\t%s\t%P\n'" | sort | while read -l -d \t date size path
                set -l f (string split -m1 / -- $path)
                printf '%s\t%s\t%s\t%s\t%s\n' $f[1] $f[2] (numfmt --to=iec $size) $date $url/(string escape --style=url -- $path)
              end | column -t -s \t
            else if set -q _flag_delete
              if not string match -qr '^[0-9a-f]{32}$' -- $_flag_delete
                echo "share: not an id: $_flag_delete" >&2
                return 1
              end
              ssh bach "rm -r $root/$_flag_delete"
            else
              # nginx refuses any path with a dotfile in it.
              if test (count $argv) -ne 1; or not test -f $argv[1]; or string match -q '.*' -- (path basename -- $argv[1])
                echo "usage: share <file> | --list | --delete <id> (no dotfiles)" >&2
                return 1
              end
              set -l name (path basename -- $argv[1])
              set -l id (od -An -N16 -tx1 /dev/urandom | string replace -a ' ' "")
              # The remote shell is fish; umask 027 leaves the directory and the file readable by nginx's group.
              ssh bach "umask 027; mkdir $root/$id && cat > $root/$id/"(string escape -- $name) <$argv[1]
              or return 1
              set -l link $url/$id/(string escape --style=url -- $name)
              echo $link
              command -q wl-copy; and wl-copy $link
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

      home.packages = [ inputs.self.packages.${pkgs.stdenv.hostPlatform.system}.configurations-man ];
    };

  # configurations(7), from the same file as the docs page. The fixed date, as in nixpkgs' own man pages, keeps the page dependent on its source only.
  perSystem =
    { pkgs, ... }:
    {
      packages.configurations-man = pkgs.runCommand "configurations-man" { nativeBuildInputs = [ pkgs.lowdown ]; } ''
        mkdir -p $out/share/man/man7
        { printf '# NAME\n\nconfigurations - shell reference for this NixOS configuration\n\n# DESCRIPTION\n'; tail -n +2 ${../../docs/shell.md}; } \
          | lowdown -s -tmdoc --roff-manpage --parse-no-metadata -M title=configurations -M section=7 -M shiftheadinglevelby=-1 -M date=1980-01-01 \
            -o $out/share/man/man7/configurations.7
      '';
    };
}
