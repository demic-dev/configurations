{ ... }:
{
  flake.homeModules.gtk =
{ pkgs, ... }:
{
  gtk = {
    enable = true;

    # GTK3 only: for GTK4 home-manager would @import adw-gtk3's nonexistent gtk-4.0/gtk.css.
    gtk3.theme = {
      package = pkgs.adw-gtk3;
      name = "adw-gtk3-dark";
    };

    colorScheme = "dark";

    # noctalia renders the palette to noctalia.css and appends this import itself,
    # clobbering home-manager's symlink; declaring it here makes its hook return early.
    gtk3.extraCss = ''
      @import url("noctalia.css");
    '';
    gtk4.extraCss = ''
      @import url("noctalia.css");
    '';
  };
}
  ;
}
