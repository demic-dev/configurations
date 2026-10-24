{ ... }:
{
  flake.homeModules.pcmanfm =
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    pcmanfm
    lxmenu-data # libfm's "Open With" chooser reads lxde-applications.menu, which only this ships
  ];

  # Everything else already defaults to what we want. force: the Preferences dialog
  # rewrites this file, and home-manager refuses to re-backup over an existing .bak.
  xdg.configFile."libfm/libfm.conf" = {
    force = true;
    text = ''
      [config]
      terminal=ghostty
    '';
  };

  # pcmanfm/default/pcmanfm.conf is deliberately unmanaged: pcmanfm rewrites it wholesale
  # on exit (window geometry, sort order), so a home-manager symlink there gets replaced
  # and every later rebuild then dies on the stale .bak.
}
  ;
}
