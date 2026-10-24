{ config, inputs, self, ... }:
let
  env = import ../../../env.nix { inherit (inputs.nixpkgs) lib; };
in
{
  flake.nixosConfigurations.bach = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit inputs self env; };
    modules = with config.flake.nixosModules; [
      impermanence
      inputs.agenix.nixosModules.default
      inputs.home-manager.nixosModules.home-manager

      # base machine + shared aspects
      bach-hardware
      core
      
      # users
      michele

      # services
      tailscale
      tailnet-server
      nginx
      acme
      postgresql
      fail2ban
      backup
      nextcloud
      immich
      calibre
      miniflux
      hugo
      static-files

      bach
      ({ pkgs, inputs, ... }: {
        nixpkgs.hostPlatform = "aarch64-linux";

        time.timeZone = "Europe/Madrid";

        systemd.coredump.settings.Coredump.Storage = "none";

        # bach builds for both hosts; keep builds from pushing the services out of RAM.
        nix.daemonCPUSchedPolicy = "batch";
        nix.daemonIOSchedClass = "idle";
        systemd.services.nix-daemon.serviceConfig = {
          MemoryMax = "3G";
          # zram is swap in RAM: without this, builds overflow MemoryMax into it unbounded.
          MemorySwapMax = "512M";
        };

        programs.fish.enable = true;

        environment.systemPackages = with pkgs; [
          inputs.agenix.packages.${pkgs.stdenv.hostPlatform.system}.default
          tailscale
          btop
          git-agecrypt
          vim
          git
          fd
          ripgrep
          git-crypt
          hugo
        ];

        # Before changing, read the option docs (man configuration.nix).
        system.stateVersion = "24.11";
      })
    ];
  };
}
