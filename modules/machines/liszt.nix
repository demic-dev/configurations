{ inputs, config, ... }:
{
  perSystem = { pkgs, lib, system, ... }: lib.mkIf (system == "x86_64-linux") {
    nix2gpu.liszt = {
      user = "root";

      tailscale.enable = true;
      # The authkey is injected at runtime as -e TAILSCALE_AUTHKEY by the VastAI template

      extraStartupScript = ''
        hostname="''${TAILSCALE_HOSTNAME:-liszt}"
        for _ in $(seq 120); do
          tailscale status >/dev/null 2>&1 && break
          sleep 0.5
        done
        tailscale set --hostname="$hostname" --accept-dns=false || true
      '';

      home = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = with config.flake.homeModules; [
          fish
          git
          {
            home.username = "root";
            home.homeDirectory = "/root";
            home.stateVersion = "26.05";
          }
        ];
      };

      # System-wide CLI tools. Python/GPU work uses uv-managed interpreters, not this python3.
      systemPackages = with pkgs; [ uv tmux curl python3 htop ripgrep ];

      exposedPorts = { "22/tcp" = { }; }; # direct sshd fallback; Tailscale SSH needs no ports
      registries = [ "ghcr.io/demic-dev" ]; # → ghcr.io/demic-dev/liszt
      tag = "latest";
    };
  };
}
