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
          };

          # Mirrors what hypridle did under hyprland: lock at 5 minutes, suspend at 10.
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
