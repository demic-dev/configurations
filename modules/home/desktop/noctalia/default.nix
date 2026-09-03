{ ... }:
{
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

          wallpaper.directory = "${config.xdg.configHome}/gruvbox-wallpapers";

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
                "obsidian"
                "vscode"
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
    };
}
