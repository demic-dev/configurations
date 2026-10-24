{ config, inputs, self, ... }:
let
  env = import ../../../env.nix { inherit (inputs.nixpkgs) lib; };
in
{
  flake.nixosConfigurations.satie = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit inputs self env; };
    modules = with config.flake.nixosModules; [
      inputs.nixos-apple-silicon.nixosModules.default
      inputs.agenix.nixosModules.default
      inputs.home-manager.nixosModules.home-manager
      inputs.noctalia-greeter.nixosModules.default

      # machine + shared + desktop aspects
      satie-hardware
      core
      desktop
      niri
      noctalia
      
      # users
      michele
      claude

      # services
      ssh
      print-scan
      # llama-cpp
      eduroam

      satie
      ({ pkgs, inputs, ... }: {
        services.tzupdate.enable = true;

        services.timesyncd = {
          enable = true;
          servers = [ "0.nixos.pool.ntp.org" "1.nixos.pool.ntp.org" "2.nixos.pool.ntp.org" "3.nixos.pool.ntp.org" ];
        };

        programs.fish.enable = true;
        programs.vim = {
          enable = true;
          defaultEditor = true;
        };

        nixpkgs.config.allowUnfree = true;
        # https://github.com/NixOS/nixpkgs/issues/526914 — remove when bitwarden ships electron 41.
        nixpkgs.config.permittedInsecurePackages = [ "electron-39.8.10" ];

        environment.systemPackages = with pkgs; [
          vim
          python3
          gnumake
          unzip
          gcc
          cargo
          rustc
          brightnessctl
          slurp
          grim
          satty
          playerctl
          nixd
          deadnix
          statix
          inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
        ];

        services.tailscale.enable = true;
      })
    ];
  };
}
