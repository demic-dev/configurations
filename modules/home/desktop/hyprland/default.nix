{ ... }:
{
  flake.homeModules.hyprland =
{ pkgs, ... }:
{
  home.packages = with pkgs; [
    hypridle
    wl-clipboard
    hyprpolkitagent
    fcitx5
  ];

  # Provide the macOS hyprcursor theme declaratively from the repo-vendored asset,
  # replacing the previously hand-placed ~/.local/share/icons/macOS-cursor directory.
  # HYPRCURSOR_THEME=macOS (set in the env block below) resolves against this. The
  # same asset is installed system-wide in modules/nixos/desktop.nix for the greeter.
  xdg.dataFile."icons/macOS-cursor".source = ../../../nixos/assets/macOS-cursor;

  systemd.user.targets.hyprland-session.Unit.Wants = [
    "xdg-desktop-autostart.target"
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    package = null;
    portalPackage = pkgs.xdg-desktop-portal-hyprland;

    configType = "hyprlang";

    xwayland = {
      enable = true;
    };

    systemd.enable = true;

    settings = {
      # Variables (define these as needed, common defaults)
      "$terminal" = "ghostty";  # or foot, kitty, etc.
      "$fileManager" = "dolphin";  # or thunar, etc.
      "$mainMod" = "SUPER";

      source = [
        "./dms/colors.conf"
        "./dms/layout.conf"
        "./dms/windowrules.conf"
      ];

      exec-once = [
        "dms run"
        # gnome-keyring (pkcs11/secrets) and gcr-ssh-agent are already started as
        # socket-activated systemd user services, so starting the daemon here again
        # only races them for the same sockets. Let systemd own it.
        "systemctl --user start hyprpolkitagent"
        "fcitx5 -d"
      ];

      env = [
        "XCURSOR_SIZE,24"
        "HYPRCURSOR_SIZE,24"
        "HYPRCURSOR_THEME,macOS"
        "XCURSOR_THEME,macOS"
        "GTK_IM_MODULE,wayland"
        "QT_IM_MODULES,wayland;fcitx;ibus"
        "XMODIFIERS,@im=fcitx"
        "GLFW_IM_MODULE,fcitx"
        "SDL_IM_MODULE,fcitx"
        # gcr-ssh-agent serves this socket (the modern replacement for gnome-keyring's
        # ssh component); confirmed live as the active SSH_AUTH_SOCK.
        "SSH_AUTH_SOCK,$XDG_RUNTIME_DIR/gcr/ssh"
        # GPG_AGENT_SOCK dropped: no gpg agent is configured and nothing listens on
        # $XDG_RUNTIME_DIR/gpg-agent, so the variable only pointed at a dead path.
      ];

      monitor = [
        ",2560x1600@144,auto,1.25"
      ];

      # General settings
      general = {
        gaps_in = 8;
        gaps_out = 0;
        border_size = 2;
        resize_on_border = true;
        allow_tearing = false;
        layout = "dwindle";
      };

      # Decoration settings
      decoration = {
        rounding = 4;
        active_opacity = 1;
        inactive_opacity = 1;
        shadow = {
          enabled = true;
          range = 4;
          render_power = 3;
          color = "rgba(1a1a1aee)";
        };
        blur = {
          enabled = true;
          size = 7;
          passes = 3;
          ignore_opacity = true;
          
          noise = 0.08;
          contrast = 1.5;

          xray = false;
          new_optimizations = true;
        };
      };

      # Animations
      animations = {
        enabled = "yes, please :)";
        bezier = [
          "easeOutQuint, 0.23, 1, 0.32, 1"
          "easeInOutCubic, 0.65, 0.05, 0.36, 1"
          "linear, 0, 0, 1, 1"
          "almostLinear, 0.5, 0.5, 0.75, 1"
          "quick, 0.15, 0, 0.1, 1"
        ];
        animation = [
          "global, 1, 10, default"
          "border, 1, 5.39, easeOutQuint"
          "windows, 1, 4.79, easeOutQuint"
          "windowsIn, 1, 4.1, easeOutQuint, popin 87%"
          "windowsOut, 1, 1.49, linear, popin 87%"
          "fadeIn, 1, 1.73, almostLinear"
          "fadeOut, 1, 1.46, almostLinear"
          "fade, 1, 3.03, quick"
          "layers, 1, 3.81, easeOutQuint"
          "layersIn, 1, 4, easeOutQuint, fade"
          "layersOut, 1, 1.5, linear, fade"
          "fadeLayersIn, 1, 1.79, almostLinear"
          "fadeLayersOut, 1, 1.39, almostLinear"
          "workspaces, 1, 1.94, almostLinear, fade"
          "workspacesIn, 1, 1.21, almostLinear, fade"
          "workspacesOut, 1, 1.94, almostLinear, fade"
          "zoomFactor, 1, 7, quick"
        ];
      };

      # Layout settings
      dwindle = {
        # pseudotile = true;
        preserve_split = true;
      };

      master = {
        new_status = "master";
      };

      # Misc settings
      misc = {
        force_default_wallpaper = 0;
        disable_hyprland_logo = true;
      };
      
      bind = [
        # Open Applications
        "$mainMod,return,exec,$terminal"
        "$mainMod,E,exec,$fileManager"
        "$mainMod,M,exec,zen"
        "$mainMod,S,exec, $terminal --command=~/repos/spotatui/result/bin/spotatui"
        "$mainMod SHIFT,M,exec, proton-authenticator"

        # Lock
        "$mainMod,L,exec,dms ipc call lock lock"

        # Manage Applications
        "$mainMod,C,killactive"
        "$mainMod,V,togglefloating"
        "$mainMod,P,pseudo"
        # "$mainMod,J,togglesplit"
        "$mainMod,F,fullscreen,0"
        "$mainMod SHIFT,W,exec,~/.config/hypr/scripts/hyprshot.sh"

        # Move focus with mainMod + vim bindings
        "$mainMod SHIFT,h,movefocus,l"
        "$mainMod SHIFT,l,movefocus,r"
        "$mainMod SHIFT,k,movefocus,u"
        "$mainMod SHIFT,j,movefocus,d"

        # Spotlight
        "$mainMod,space,exec,dms ipc call spotlight toggle"
        # Keybinds Helper
        "$mainMod,.,exec,dms ipc call keybinds toggle hyprland"
      ] ++ (
        # Switch to workspace (keys 1..9,0 -> workspaces 1..10)
        builtins.genList (i: let ws = i + 1; key = if ws == 10 then 0 else ws; in
          ''$mainMod, ${toString key}, workspace, ${toString ws}'') 10 ++
        # Move to Workspace
        builtins.genList (i: let ws = i + 1; key = if ws == 10 then 0 else ws; in
          ''$mainMod SHIFT, ${toString key}, movetoworkspace, ${toString ws}'') 10
      );

      # # Scroll through existing workspaces
      # bind = [
      #   "$mainMod,mouse_down,workspace,e+1"
      #   "$mainMod,mouse_up,workspace,e-1"
      # ];
    
      binde = [
        # Resize windows
        "$mainMod SHIFT,p,resizeactive,-50 0"
        "$mainMod SHIFT,n,resizeactive,50 0"
      ];
      
      # Move/resize windows with mainMod + LMB/RMB
      bindm = [
        "$mainMod,mouse:272,movewindow"
        "$mainMod,mouse:273,resizewindow"
      ];
      
      # Laptop multimedia keys for volume
      bindel = [
        # Volume
        ",XF86AudioRaiseVolume,exec, dms ipc call audio increment 5"
        ",XF86AudioLowerVolume,exec, dms ipc call audio decrement 5"
        ",XF86AudioMute,exec, dms ipc call audio mute"
        ",XF86AudioMicMute,exec, dms ipc call audio micmute"

        # Screen Brightness
        ",XF86MonBrightnessUp,exec, dms ipc call brightness increment 10 \"\""
        ",XF86MonBrightnessDown,exec, dms ipc call brightness decrement 10 \"\""

        # Keyboard Brightness
        "$mainMod,XF86MonBrightnessUp,exec, dms ipc call brightness increment 10 \"leds:kbd_backlight\""
        "$mainMod,XF86MonBrightnessDown,exec, dms ipc call brightness decrement 10 \"leds:kbd_backlight\""
      ];
    
    
      # Media controls
      bindl = [
        ",XF86AudioNext,exec, dms ipc call mpris next"
        ",XF86AudioPause,exec, dms ipc call mpris playPause"
        ",XF86AudioPlay,exec, dms ipc call mpris playPause"
        ",XF86AudioPrev,exec, dms ipc call mpris previous"
      ];

      # Input configuration
      input = {
        kb_layout = "us";
        kb_options = "compose:rwin";
        follow_mouse = 1;
        sensitivity = 0.2;
        scroll_method = "2fg";
        touchpad = {
          natural_scroll = true;
          tap-to-click = true;
          drag_lock = false;
          disable_while_typing = true;
          tap_button_map = "lrm";
          clickfinger_behavior = true;
        };
      };

      # Gestures
      gesture = [ "3,horizontal,workspace" ];
    };
  };

  services.hypridle = {
    enable = true;

    package = pkgs.hypridle;

    settings = {
      general = {
        lock_cmd = "dms ipc call lock lock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };

      listener = [
        # Lock the screen
        {
          timeout = 300;
          on-timeout = "loginctl lock-session";
        }
        # Turn off screen
        {
            timeout = 310;
            on-timeout = "~/.config/hypr/scripts/lock-properly.sh off";
            on-resume = "~/.config/hypr/scripts/lock-properly.sh on";
        }
        # Suspend the system
        {
            timeout = 600;
            on-timeout = "systemctl suspend";
        }
      ];
    };
  };

  xdg.configFile."hypr/scripts" = {
    source = ./config/scripts;
    recursive = true;
  };
}
  ;
}
