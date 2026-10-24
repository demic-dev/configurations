{ config, ... }:
let
  hm = config.flake.homeModules;
in
{
  flake.nixosModules.satie =
    { config, env, inputs, ... }:
    {
      users.users.michele = {
        hashedPasswordFile = config.age.secrets.michele-password.path;
        openssh.authorizedKeys.keys = [ env.userSettings.bach.ssh.michele.value ];
      };

      age.secrets.michele-password.file = ../../../secrets/michele-password.age;
      age.secrets.michele-at-satie = {
        file = ../../../secrets/michele-at-satie.age;
        path = env.userSettings.satie.ssh.michele.location;
        owner = "michele";
        group = "users";
        mode = "600";
      };

      # Dedicated PASSPHRASELESS key used ONLY by git-agecrypt to decrypt secrets/sensitive/*.age silently. The login key above is passphrase-protected, which makes git-agecrypt prompt on every git command; this key avoids that. Its public key is a recipient in root/git-agecrypt.toml, and the git home module points git-agecrypt at this path.
      age.secrets.git-agecrypt-key = {
        file = ../../../secrets/git-agecrypt-key.age;
        path = env.userSettings.satie.ssh.git-agecrypt.location;
        owner = "michele";
        group = "users";
        mode = "600";
      };

      # agenix (not home-manager) owns the git email files because the user's ssh key is passphrase-protected, which breaks home-manager's agenix integration.
      age.secrets.git-email = {
        file = ../../../secrets/git-email.age;
        owner = "michele";
        group = "repos";
        mode = "0440";
      };
      age.secrets.noreply-github-email = {
        file = ../../../secrets/noreply-github-email.age;
        owner = "michele";
        group = "repos";
        mode = "0440";
      };

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "bak";
      home-manager.extraSpecialArgs = { inherit inputs; };
      home-manager.users.michele = { pkgs, ... }: {
        home.username = "michele";
        home.homeDirectory = "/home/michele";

        imports = with hm; [
          git
          ghostty
          fish
          # hister
          niri
          noctalia
          nvim
          gtk
          pcmanfm
          xdg
          zen
        ];

        services.udiskie = {
          enable = true;
          settings.program_options.file_manager = "${pkgs.pcmanfm}/bin/pcmanfm";
        };

        services.gnome-keyring = {
          enable = true;
          components = [ "pkcs11" "secrets" ];
        };

        home.packages = with pkgs; [
          # Its tests recompile the whole crate with thin LTO and one codegen unit, which OOMs under bach's build cap.
          # (inputs.fastpotify.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs { doCheck = false; })
          proton-authenticator
          anki
          zip
          p7zip
          sc-im
          loupe
          gcr_3
          seahorse
          libsecret
          xdg-utils
          bitwarden-desktop
          signal-desktop
          vesktop
          # calibre
          nextcloud-client
          chromium
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

          zathura = {
            enable = true;
            options = {
              selection-clipboard = "clipboard";
              recolor = true;
            };
            extraConfig = "include noctaliarc";
          };

          bash.enable = true;

          # `update` comes from the shared fish home module.
          fish.enable = true;
        };

        home.file.".ssh/id_ed25519.pub".text = env.userSettings.satie.ssh.michele.value;

        home.stateVersion = "26.05";
        programs.home-manager.enable = true;
      };

      home-manager.users.claude = { ... }: {
        home.username = "claude";
        home.homeDirectory = "/home/claude";

        imports = with hm; [ git ];

        programs.direnv = {
          enable = true;
          enableBashIntegration = true;
          nix-direnv.enable = true;
        };

        home.stateVersion = "26.05";
      };
    };
}
