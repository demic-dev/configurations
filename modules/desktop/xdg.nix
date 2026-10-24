{ ... }:
{
  flake.homeModules.xdg =
{ pkgs, ... }:
{
  xdg = {
    portal = {
      enable = true;
      xdgOpenUsePortal = false;
      config = {
        common.default = [ "gtk" ];
        hyprland.default = [
          "gtk"
          "hyprland"
        ];
        # This user config shadows the system one that programs.niri writes, so niri's
        # screencast portal has to be repeated here or it falls back to plain gtk.
        niri.default = [
          "gnome"
          "gtk"
        ];
      };
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    mimeApps = {
        enable = true;
        defaultApplications = {
            "x-scheme-handler/http" = "zen-beta.desktop";
            "x-scheme-handler/https" = "zen-beta.desktop";
            "x-scheme-handler/about" = "zen-beta.desktop";
            "x-scheme-handler/unknown" = "zen-beta.desktop";
            "text/html" = "zen-beta.desktop";

            "application/pdf" = "org.pwmt.zathura-pdf-mupdf.desktop";

            "inode/directory" = "pcmanfm.desktop";
        };
    };
  };
}
  ;
}
