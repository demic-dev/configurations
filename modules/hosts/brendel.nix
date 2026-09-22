{ config, inputs, self, ... }:
let
  env = import ../../env.nix { inherit (inputs.nixpkgs) lib; };
in
{
  flake.nixosConfigurations.brendel = inputs.nixpkgs.lib.nixosSystem {
    system = "aarch64-linux";
    specialArgs = { inherit inputs self env; };
    modules = with config.flake.nixosModules; [
      # inputs.agenix.nixosModules.default

      # users
      michele

      # services
      ssh
      tailscale

      ({ pkgs, ... }: {
        nixpkgs.hostPlatform = "armv7l-linux";

        time.timeZone = "Europe/Madrid";

        environment.systemPackages = with pkgs; [
          tailscale
          git
        ];

        # Before changing, read the option docs (man configuration.nix).
        system.stateVersion = "26.11";
      })
    ];
  };
}
