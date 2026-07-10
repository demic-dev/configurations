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

      # Bitwarden is installed per-user via home-manager, so its polkit action
      # lands in the user profile where the system polkit daemon never looks.
      # Expose just the .policy at system level so the "Unlock with system
      # authentication" action (com.bitwarden.Bitwarden.unlock) is registered
      # with polkitd; the rule below then auto-approves it. Keeps the ~200MB app
      # out of the system profile. NOTE: this only covers the polkit side — the
      # app's own setup routine additionally insists on finding the policy at the
      # hardcoded path /usr/share/polkit-1/actions (see the tmpfiles rule below),
      # otherwise it aborts biometric enrollment with "Failed to set up polkit
      # policy" and never writes the unlock key to the keyring.
      bitwardenPolkitAction = pkgs.runCommandLocal "bitwarden-polkit-action" { } ''
        mkdir -p "$out/share/polkit-1/actions"
        cp ${pkgs.bitwarden-desktop}/share/polkit-1/actions/com.bitwarden.Bitwarden.policy \
           "$out/share/polkit-1/actions/"
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
    # Silently approve Bitwarden's keyring-unlock for the active local session so
    # the desktop app opens already unlocked (no master password / polkit prompt).
    # Trade-off: vault security then rests on the login session + keyring, both of
    # which unlock at login. The action defaults to auth_self without this.
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "com.bitwarden.Bitwarden.unlock" &&
            subject.active && subject.local) {
          return polkit.Result.YES;
        }
      });
    '';
    # Bitwarden's biometric setup writes its polkit policy to a hardcoded
    # /usr/share/polkit-1/actions path; on NixOS that tree is read-only, so the
    # write fails and enrollment aborts. Pre-place the file (symlinked to the
    # app's own copy) so the check passes and the app skips the write.
    systemd.tmpfiles.rules = [
      "L+ /usr/share/polkit-1/actions/com.bitwarden.Bitwarden.policy - - - - ${pkgs.bitwarden-desktop}/share/polkit-1/actions/com.bitwarden.Bitwarden.policy"
    ];

    security.pam.services.greetd.enableGnomeKeyring = true;
    services.gnome.gnome-keyring.enable = true;
    # gcr provides the gcr-ssh-agent / pkcs11 D-Bus services the keyring relies on.
    services.dbus.packages = [ pkgs.gcr ];

    # Bluetooth audio: headphones connect but WirePlumber leaves the card in the "off"/headset profile on reconnect, so no output sink appears. Prefer AAC and force A2DP as the default profile
    services.pipewire.wireplumber.extraConfig."10-bluez" = {
      "monitor.bluez.properties" = {
        "bluez5.enable-sbc-xq" = true;
        "bluez5.enable-msbc" = true;
        "bluez5.enable-hw-volume" = true;
        "bluez5.roles" = [ "a2dp_sink" "a2dp_source" "bap_sink" "bap_source" "hsp_hs" "hfp_hf" ];
        "bluez5.codecs" = [ "aac" "sbc_xq" "sbc" ];
        "bluez5.autoswitch-profile" = true;
      };
      "monitor.bluez.rules" = [
        {
          matches = [ { "device.name" = "~bluez_card.*"; } ];
          actions.update-props."device.profile" = "a2dp-sink";
        }
      ];
    };

    services.logind.settings.Login.HandlePowerKey = "ignore";

    services.upower.enable = true;
    services.power-profiles-daemon.enable = true;
    services.udisks2.enable = true;
    services.udev.enable = true;

    fonts.packages = builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [ tinymist ];

    environment.systemPackages = [ macosCursor bitwardenPolkitAction ];

    environment.pathsToLink = [
      "/share/applications"
      "/share/xdg-desktop-portal"
      # Ensure share/icons is linked into the system profile so the vendored macOS
      # hyprcursor theme is discoverable via XDG_DATA_DIRS (greeter user has no home).
      "/share/icons"
    ];
  };
}
