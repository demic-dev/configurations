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
      };
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    # KDE/Dolphin relies on this file to build its internal database of applications.
    # Without it, `kbuildsycoca6` crashes on Hyprland, causing Dolphin to forget default apps.
    configFile."menus/applications.menu".text = ''
      <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
          "http://www.freedesktop.org/standards/menu-spec/menu-1.0.dtd">
      <Menu>
        <Name>Applications</Name>
        <DefaultAppDirs/>
        <DefaultDirectoryDirs/>
        <DefaultMergeDirs/>
      </Menu>
    '';

    mimeApps = {
        enable = true;
        defaultApplications = {
            "x-scheme-handler/http" = "zen-beta.desktop";
            "x-scheme-handler/https" = "zen-beta.desktop";
            "x-scheme-handler/about" = "zen-beta.desktop";
            "x-scheme-handler/unknown" = "zen-beta.desktop";
            "text/html" = "zen-beta.desktop";

            "application/pdf" = "org.pwmt.zathura-pdf-mupdf.desktop";
        };
    };
  };
}
  ;
}
