# Desktop home aspects (satie)

home-manager aspects for the Hyprland + DankMaterialShell (DMS) desktop. Each registers a
`flake.homeModules.<name>` and is imported by `modules/hosts/satie.nix`. The matching
graphical **system** stack (greeter, polkit, keyring, portals, fonts) lives in
`modules/nixos/desktop.nix`.

| Aspect               | What it does |
|----------------------|--------------|
| `hyprland`           | Hyprland compositor config (monitors, keybinds, animations, `exec-once`). Sources DMS's generated `dms/*.conf` at runtime. |
| `dms`                | DankMaterialShell + danksearch; declarative `settings.json`; zen-browser userChrome link. |
| `xdg`                | XDG portals (gtk + hyprland), MIME defaults (zen, zathura), Dolphin menu fix. |
| `kdeconnect`         | KDE Connect. |

Toggle any of these by commenting its name out of satie's home imports list.
