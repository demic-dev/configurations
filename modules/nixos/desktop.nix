{ ... }:
{
  # Graphical SYSTEM stack (Hyprland + DankMaterialShell greeter + keyring/portal plumbing).
  # Host-specific bits (hostName, networking, users, secrets, timezone, packages) stay inline
  # in the host file — this aspect is the reusable desktop base.
  flake.nixosModules.desktop = { config, lib, pkgs, env, ... }:
    let
      # Resolve the desktop user's home from env by the host being built, so adding another
      # desktop host only needs an env.userSettings.<host> entry — no edit here.
      homePath = env.userSettings.${config.networking.hostName}.home.path;

      # Vendored hyprcursor theme, installed system-wide so the greeter user (home
      # /var/empty) can resolve it via XDG_DATA_DIRS — the user session finds the same
      # theme from ~/.local/share/icons, but the greeter never sees that.
      macosCursor = pkgs.runCommandLocal "macos-cursor" { } ''
        mkdir -p "$out/share/icons"
        cp -r ${./assets/macOS-cursor} "$out/share/icons/macOS-cursor"
      '';
    in
    {
    programs.hyprland.enable = true;

    programs.dank-material-shell.greeter = {
      enable = true;
      compositor.name = "hyprland";
      # The greeter runs its own Hyprland instance as the greeter user. Without a
      # monitor rule here Hyprland falls back to defaults, giving the wrong resolution
      # and an oversized greeter. Keep this in sync with the user session monitor line
      # in modules/home/desktop/hyprland/default.nix.
      # Mirror the user session's monitor + cursor env (modules/home/desktop/hyprland).
      # The macOS hyprcursor theme is provided system-wide via environment.systemPackages
      # below, so the greeter's Hyprland can resolve HYPRCURSOR_THEME here. Only the
      # hyprcursor vars are set: the greeter runs a single Qt Wayland shell under Hyprland
      # with no XWayland/XCursor clients, so XCURSOR_THEME/XCURSOR_SIZE would be inert.
      compositor.customConfig = ''
        monitor = ,2560x1600@144,auto,1.25
        env = HYPRCURSOR_THEME,macOS
        env = HYPRCURSOR_SIZE,24
      '';
      configHome = lib.removeSuffix "/" homePath;
      configFiles = [ "${homePath}.config/DankMaterialShell/settings.json" ];
    };

    security.polkit.enable = true;
    security.pam.services.greetd.enableGnomeKeyring = true;
    services.gnome.gnome-keyring.enable = true;
    # gcr provides the gcr-ssh-agent / pkcs11 D-Bus services the keyring relies on.
    services.dbus.packages = [ pkgs.gcr ];

    services.logind.settings.Login.HandlePowerKey = "ignore";

    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;
    services.udisks2.enable = true;
    services.udev.enable = true;

    fonts.packages = builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [ tinymist ];

    environment.systemPackages = [ macosCursor ];

    environment.pathsToLink = [
      "/share/applications"
      "/share/xdg-desktop-portal"
      # Ensure share/icons is linked into the system profile so the vendored macOS
      # hyprcursor theme is discoverable via XDG_DATA_DIRS (greeter user has no home).
      "/share/icons"
    ];
  };
}
