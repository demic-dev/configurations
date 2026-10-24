{ ... }:
{
  flake.nixosModules.noctalia =
    { config, env, ... }:
    {
      services.displayManager.noctalia-greeter = {
        enable = true;

        settings = {
          session.default = "Niri";
          user.default = env.userSettings.${config.networking.hostName}.user;

          appearance.theme_mode = "dark";

          output = {
            width = 2560;
            height = 1600;
            scale = 1.25;
          };

          cursor = {
            theme = "Adwaita";
            size = 24;
          };

          keyboard = {
            layout = "us";
            options = "compose:rwin";
          };
        };
      };
    };

  flake.homeModules.noctalia =
    { inputs, config, ... }:
    {
      imports = [ inputs.noctalia.homeModules.default ];

      programs.noctalia = {
        enable = true;
        systemd.enable = true;

        settings = {
          shell = {
            polkit_agent = true;
            niri_overview_type_to_launch_enabled = true;
          };

          theme = {
            mode = "dark";
            source = "wallpaper";

            templates = {
              builtin_ids = [ "gtk3" "gtk4" "ghostty" "niri" "qt" ];
              community_ids = [
                "claude-code"
                "discord"
                "fastfetch"
                "lazygit"
                "neovim"
                "zathura"
                "zen-browser"
              ];
            };
          };

          idle.behavior = {
            lock = {
              enabled = true;
              timeout = 300;
              action = "lock";
            };
            lock-and-suspend = {
              enabled = true;
              timeout = 600;
              action = "lock_and_suspend";
            };
          };
        };
      };

      # noctalia exits when kicked off the system bus (dbus-broker per-UID quota); the default start limit gives up
      # after a few instant failures, leaving niri locked with no lock surface (solid red screen). Keep retrying.
      systemd.user.services.noctalia = {
        Unit.StartLimitIntervalSec = 0;
        Service.RestartSec = 3;
      };
    };
}
