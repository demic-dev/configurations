{ ... }:
{
  flake.homeModules.dms =
{ pkgs, inputs, config, ... }:
{
   imports = [
    inputs.dms.homeModules.dank-material-shell
    # inputs.dms-plugin-registry.modules.default
    inputs.danksearch.homeModules.default
  ];

  programs.dank-material-shell = {
    enable = true;

    enableSystemMonitoring = true;
    dgop.package = inputs.dgop.packages.${pkgs.stdenv.hostPlatform.system}.default;

    enableDynamicTheming = true;       # Wallpaper-based theming (matugen)
    enableAudioWavelength = true;      # Audio visualizer (cava)
    enableCalendarEvents = true;       # Calendar integration (khal)
    enableClipboardPaste = true;       # Pasting items from the clipboard (wtype)
  };

  programs.dsearch = {
    enable = true;
  };

  home.file = {
    # Activation script finds profile + creates symlink
    ".config/zen-link".text = ''
      #!/bin/sh
      PROFILE_DIR=$(find ~/.config/zen -maxdepth 2 -type d -name "*.Default Profile" | head -n1)
      [ -n "$PROFILE_DIR" ] || exit 1
      mkdir -p "$PROFILE_DIR/chrome"
      ln -sf ${config.xdg.configHome}/DankMaterialShell/zen.css "$PROFILE_DIR/chrome/userChrome.css"
    '';
    ".config/zen-link".executable = true;
  };

  # By enabling the lines below, the config is always declarative and it is enforced at each rebuild
  xdg.configFile."DankMaterialShell/settings.json" = {
    force = true;
    source = ./settings.json;
  };
}
  ;
}
