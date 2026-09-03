{ ... }:
{
  flake.nixosModules.desktop = { config, lib, pkgs, env, ... }:
    let
      # Bitwarden is installed per-user via home-manager, so its polkit action lands in the user profile where the system polkit daemon never looks.
      bitwardenPolkitAction = pkgs.runCommandLocal "bitwarden-polkit-action" { } ''
        mkdir -p "$out/share/polkit-1/actions"
        cp ${pkgs.bitwarden-desktop}/share/polkit-1/actions/com.bitwarden.Bitwarden.policy \
           "$out/share/polkit-1/actions/"
      '';
    in
    {
    programs.niri.enable = true;

    programs.noctalia-greeter = {
      enable = true;

      settings = {
        session.default = "Niri";
        user.default = env.userSettings.${config.networking.hostName}.user;

        appearance.theme_mode = "dark";

        output = {
          width = 2560;
          height = 1600;
          scale = 1.25;
        };

        cursor = {
          theme = "Adwaita";
          size = 24;
        };

        keyboard = {
          layout = "us";
          options = "compose:rwin";
        };
      };
    };

    security.polkit.enable = true;
    # Silently approve Bitwarden's keyring-unlock for the active local session so the desktop app opens already unlocked (no master password / polkit prompt).
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "com.bitwarden.Bitwarden.unlock" &&
            subject.active && subject.local) {
          return polkit.Result.YES;
        }
      });
    '';
    # Bitwarden's biometric setup writes its polkit policy to a hardcoded /usr/share/polkit-1/actions path; on NixOS that tree is read-only, so the write fails and enrollment aborts. Pre-place the file (symlinked to the app's own copy) so the check passes and the app skips the write.
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
    services.gvfs.enable = true;
    services.udev.enable = true;

    fonts.packages = builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [ tinymist ];

    environment.systemPackages = [ bitwardenPolkitAction pkgs.adwaita-icon-theme ];

    environment.pathsToLink = [
      "/share/applications"
      "/share/xdg-desktop-portal"
      # Ensure share/icons is linked into the system profile so the greeter, which has no home, can resolve cursors via XDG_DATA_DIRS.
      "/share/icons"
    ];
  };
}
