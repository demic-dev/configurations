{ config, ... }:
{
  flake.homeModules.niri =
    { pkgs, ... }:
    {
      imports = [ config.flake.homeModules.screenshot-niri ];

      home.packages = with pkgs; [
        wl-clipboard
        xwayland-satellite
      ];

      # niri has no hyprcursor support, so the vendored macOS theme cannot follow us here.
      home.pointerCursor = {
        enable = true;
        package = pkgs.adwaita-icon-theme;
        name = "Adwaita";
        size = 24;
        gtk.enable = true;
      };

      xdg.configFile."niri/config.kdl".source = ./config.kdl;
    };
}
