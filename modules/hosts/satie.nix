{ config, inputs, self, ... }:
let
  env = import ../../env.nix { inherit (inputs.nixpkgs) lib; };
  # Bound here so the home-manager user module (a function taking its own `config`) can still
  # reach the flake-level home aspects without the arg shadowing config.flake.
  hm = config.flake.homeModules;
in
{
  flake.nixosConfigurations.satie = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit inputs self env; };
    modules = with config.flake.nixosModules; [
      inputs.nixos-apple-silicon.nixosModules.default
      inputs.agenix.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
      inputs.dms.nixosModules.greeter

      # machine + shared + desktop aspects
      satie-hardware
      core
      desktop
      
      # users
      michele

      ({ config, pkgs, lib, ... }: {
        networking = {
          hostName = env.userSettings.satie.host;
          hostId = env.userSettings.satie.id;
          nameservers = env.userSettings.satie.network.nameservers;
        
          networkmanager = {
            enable = true;
            wifi.backend = "iwd";
            wifi.powersave = false;
            wifi.macAddress = "random";
          };

          firewall = rec {
            enable = true;
            allowedTCPPorts = [ 59520 ]; # Calibre wireless device connection
            allowedUDPPorts = allowedTCPPorts;
          };
        };


        time.timeZone = "Europe/Amsterdam";

        users.users.michele = {
          hashedPasswordFile = config.age.secrets.michele-password.path;
          openssh.authorizedKeys.keys = [ env.userSettings.satie.publicSSH ];
        };

        programs.fish.enable = true;
        programs.vim = {
          enable = true;
          defaultEditor = true;
        };

        nixpkgs.config.allowUnfree = true;
        # https://github.com/NixOS/nixpkgs/issues/526914 — remove when bitwarden ships electron 41.
        nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];

        environment.systemPackages = with pkgs; [
          vim
          openssh
          python3
          gnumake
          unzip
          gcc
          cargo
          rustc
          brightnessctl
          slurp
          grim
          satty
          playerctl
          nixd
          deadnix
          statix
          inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
        ];

        services.tailscale.enable = true;

        services.openssh = {
          enable = true;
          hostKeys = [{
            type = "ed25519";
            path = "/etc/ssh/ssh_host_ed25519_key";
          }];
        };

        age.secrets.michele-password.file = ../../secrets/michele-password.age;
        age.secrets.michele-at-satie = {
          file = ../../secrets/michele-at-satie.age;
          path = "/home/michele/.ssh/id_ed25519";
          owner = "michele";
          group = "users";
          mode = "600";
        };

        # Dedicated PASSPHRASELESS key used ONLY by git-agecrypt to decrypt secrets/sensitive/*.age
        # silently. The login key above is passphrase-protected, which makes git-agecrypt prompt on
        # every git command; this key avoids that. Its public key is a recipient in
        # root/git-agecrypt.toml, and the git home module points git-agecrypt at this path.
        age.secrets.git-agecrypt-key = {
          file = ../../secrets/git-agecrypt-key.age;
          path = "/home/michele/.ssh/git-agecrypt_ed25519";
          owner = "michele";
          group = "users";
          mode = "600";
        };

        # agenix (not home-manager) owns the git email files because the user's ssh key is passphrase-protected, which breaks home-manager's agenix integration.
        age.secrets.git-email = {
          file = ../../secrets/git-email.age;
          owner = "michele";
          group = "users";
        };
        age.secrets.noreply-github-email = {
          file = ../../secrets/noreply-github-email.age;
          owner = "michele";
          group = "users";
        };

        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "bak";
        home-manager.extraSpecialArgs = { inherit inputs; };
        home-manager.users.michele = { pkgs, inputs, ... }: {
          home.username = "michele";
          home.homeDirectory = "/home/michele";

          imports = with hm; [
            git
            ghostty
            fish
            hyprland
            dms
            xdg
            gruvbox-wallpapers
          ];

          services.udiskie = {
            enable = true;
            settings.program_options.file_manager = "${pkgs.kdePackages.dolphin}/bin/dolphin";
          };

          services.gnome-keyring = {
            enable = true;
            components = [ "pkcs11" "secrets" "ssh" ];
          };

          home.packages = with pkgs; [
            claude-code
            proton-authenticator
            anki
            git-agecrypt
            zip
            p7zip
            sc-im
            loupe
            gcr
            seahorse
            libsecret
            xdg-utils
            bitwarden-desktop
            signal-desktop
            neovim
            vesktop
            zathura
            calibre
            nextcloud-client
            chromium
            kdePackages.dolphin
            kdePackages.kde-cli-tools
            obsidian
            vscodium
            librepods
            vimPlugins.typst-preview-nvim
            websocat # websocket client required by TypstPreview
          ];

          programs = {
            direnv = {
              enable = true;
              enableBashIntegration = true;
              nix-direnv.enable = true;
            };

            ssh = {
              enable = true;
              enableDefaultConfig = false;

              settings."github.com" = {
                User = "git";
                IdentityFile = "~/.ssh/id_ed25519";
                AddKeysToAgent = "yes";
              };
            };

            bash.enable = true;

            # `update` / `update-remote` come from the shared fish home module.
            fish.enable = true;
          };

         home.file.".ssh/id_ed25519.pub".text = env.userSettings.satie.publicSSH;

          home.stateVersion = "26.05";
          programs.home-manager.enable = true;
        };
      })
    ];
  };
}
