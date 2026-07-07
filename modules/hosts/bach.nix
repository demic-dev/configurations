{ config, inputs, self, ... }:
let
  env = import ../../env.nix { inherit (inputs.nixpkgs) lib; };
in
{
  flake.nixosConfigurations.bach = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit inputs self env; };
    modules = with config.flake.nixosModules; [
      inputs.impermanence.nixosModules.impermanence
      inputs.agenix.nixosModules.default
      inputs.home-manager.nixosModules.home-manager

      # base machine + shared aspects
      bach-hardware
      core
      
      # users
      michele

      # services
      ssh
      tailscale
      nginx
      acme
      postgresql
      fail2ban
      backup
      nextcloud
      immich
      calibre
      miniflux
      hugo
      ghost
      static-files

      ({ pkgs, ... }: {
        nixpkgs.hostPlatform = "aarch64-linux";

        networking = {
          hostName = env.userSettings.bach.host;
          hostId = env.userSettings.bach.id;
          nameservers = env.userSettings.bach.network.nameservers;

          networkmanager.enable = false;

          interfaces.enp7s0 = {
            useDHCP = false;
            ipv4.addresses = [{ address = env.userSettings.bach.network.ip.v4; prefixLength = 22; }];
            ipv6.addresses = [{ address = env.userSettings.bach.network.ip.v6; prefixLength = 64; }];
          };

          # Since the systemd stage-1 initrd migration, interface must be set
          # explicitly: nixpkgs only copies the default route into the initrd's
          # networkd config (40-enp7s0.network) when it is non-null, and without
          # it stage-1 SSH unlock is unreachable from outside the subnet.
          defaultGateway = {
            address = env.userSettings.bach.network.gateway;
            interface = "enp7s0";
          };
          firewall.enable = true;
        };
        # Pins uids/gids for system accounts that NixOS would otherwise allocate dynamically.
        # Needed because /var/lib/nixos (where those allocations are recorded) isn't persisted, so an unpinned id could shift on every reboot of this impermanence-wiped root.
        users.users.dhcpcd.uid = 997;
        users.groups.dhcpcd.gid = 997;

        users.users.mandb.uid = 980;
        users.groups.mandb.gid = 980;

        users.users.nscd.uid = 981;
        users.groups.nscd.gid = 981;

        users.users.systemd-oom.uid = 982;
        users.groups.systemd-oom.gid = 982;

        users.groups.resolvconf.gid = 983;
        users.groups.systemd-coredump.gid = 984;

        virtualisation.docker.enable = true;
        virtualisation.oci-containers.backend = "docker";

        time.timeZone = "Europe/Madrid";

        programs.fish.enable = true;

        environment.systemPackages = with pkgs; [
          inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
          tailscale
          btop
          gcc
          git-agecrypt
          vim
          git
          fd
          ripgrep
          git-crypt
          zathura
          texliveFull
          pandoc
          go
          hugo
        ];
        users.mutableUsers = false;
        users.users.root.initialHashedPassword = "$6$9joJdfYW9u7849iq$5jFEhesBUwM6yvSA8g8iMiog15pFTOIOEF28zzmgB2P1evUludMC0vboBsCFDylCvQWw6WFu8tc7VkhMjYKzr.";

        users.users.michele = {
          extraGroups = [ "docker" ];
          initialHashedPassword = "$6$DptngetaTDY6G.qa$tEWVAEGlpkvzUltZXYaZpQz4c40KOQG3eQXhwhcQn33oM02NyemgBFSa/G6Mzb9iKbTroI7uKd7AWgBfKuUGF.";
          openssh.authorizedKeys.keys = [
            env.userSettings.satie.ssh.michele.value
          ];
        };

        age.secrets.git-email = {
          file = ../../secrets/git-email.age;
          owner = env.userSettings.bach.user;
          group = "users";
        };
        age.secrets.noreply-github-email = {
          file = ../../secrets/noreply-github-email.age;
          owner = env.userSettings.bach.user;
          group = "users";
        };

        # Before changing, read the option docs (man configuration.nix).
        system.stateVersion = "24.11";

        age.secrets.michele-at-bach = {
          file = ../../secrets/michele-at-bach.age;
          path = env.userSettings.bach.ssh.michele.location;
          owner = "michele";
          group = "users";
          mode = "600";
        };

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = { inherit env inputs; };
        home-manager.users.michele = {
          imports = with config.flake.homeModules; [ git fish ghostty ];

          home.username = "michele";
          # Must not have a trailing slash: home-manager's nixos module already derives this from
          # users.users.michele.home ("/home/michele"), and a mismatching value is a hard conflict.
          # (env...home.path keeps its trailing slash for the XDG_CONFIG_HOME concatenation below.)
          home.homeDirectory = "/home/michele";

          programs.neovim.enable = true;
          programs.neovim.withRuby = false;
          programs.neovim.withPython3 = false;

          # `update` / `update-remote` come from the shared fish home module.

          home.sessionVariables = {
            EDITOR = "nvim";
            XDG_CONFIG_HOME = "${env.userSettings.bach.home.path}.config";
          };

          home.stateVersion = "23.05";
          programs.home-manager.enable = true;
        };
      })
    ];
  };
}
