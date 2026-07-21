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

        # git email routing, injected at runtime (agenix can't reach a throwaway host): default to
        # GIT_EMAIL, override with GIT_NOREPLY_EMAIL on github remotes — same routing as satie/bach.
        # Written to ~/.gitconfig, which git reads on top of the home-manager ~/.config/git/config.
        if [ -n "''${GIT_EMAIL:-}" ]; then
          printf '[user]\n\temail = %s\n' "''${GIT_EMAIL}" > /root/.gitconfig
          if [ -n "''${GIT_NOREPLY_EMAIL:-}" ]; then
            printf '[user]\n\temail = %s\n' "''${GIT_NOREPLY_EMAIL}" > /root/.gitconfig.github
            {
              printf '[includeIf "hasconfig:remote.*.url:git@github.com:*/**"]\n\tpath = /root/.gitconfig.github\n'
              printf '[includeIf "hasconfig:remote.*.url:https://github.com/**"]\n\tpath = /root/.gitconfig.github\n'
            } >> /root/.gitconfig
          fi
        fi
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
