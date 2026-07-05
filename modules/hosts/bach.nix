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

          defaultGateway = env.userSettings.bach.network.gateway;
          firewall.enable = true;
        };
        users.users.dhcpcd.uid = 997;

        virtualisation.docker.enable = true;
        virtualisation.oci-containers.backend = "docker";

        time.timeZone = "Europe/Madrid";

        programs.fish.enable = true;

        environment.systemPackages = with pkgs; [
          inputs.agenix.packages.${pkgs.system}.default
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
            env.userSettings.bach.publicSSH
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
