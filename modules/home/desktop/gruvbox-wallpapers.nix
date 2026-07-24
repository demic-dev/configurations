{ ... }:
{
  flake.homeModules.gruvbox-wallpapers =
{
  inputs,
  pkgs,
  ...
}: {
  xdg.configFile."gruvbox-wallpapers" = {
    source = inputs.gruvbox-wallpapers.packages."${pkgs.stdenv.hostPlatform.system}".default;
    recursive = true;
  };
}
  ;
}
