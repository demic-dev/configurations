{ inputs, config, ... }:
{
  perSystem = { pkgs, lib, system, ... }:
    let
      # ollama needs a CUDA-enabled nixpkgs to use the rented GPU; our default `pkgs` has neither
      # allowUnfree nor cudaSupport. Import nixpkgs once more just for it (CI pulls the build from
      # the CUDA caches wired into the liszt-image workflow).
      cudaPkgs = import inputs.nixpkgs {
        inherit system;
        config = { allowUnfree = true; cudaSupport = true; };
      };
    in
    lib.mkIf (system == "x86_64-linux") {
    nix2gpu.liszt = {
      user = "root";

      # Tailscale SSH launches the /etc/passwd login shell; nix2gpu defaults root to bash (its
      # stock home configures bash), but we ship fish. Point the login shell at our fish so
      # `ssh root@liszt` lands in it. PATH is restored by the fish conf.d snippet in `home` below.
      nix2gpuUsers.root.shell = lib.mkForce "${pkgs.fish}/bin/fish";

      tailscale.enable = true;
      # The authkey is injected at runtime as -e TAILSCALE_AUTHKEY by the VastAI template

      extraStartupScript = ''
        # nix2gpu 0.1.0 ships /etc/ssl/certs/ca-bundle.crt as a *relative* symlink
        # (create-base-system.sh: `ln -s cacert/etc/...`) that resolves nowhere, so every TLS
        # client following SSL_CERT_FILE fails with a bad-CA error. Repair it to the real bundle.
        ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt
        ln -sf ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt

        # nix2gpu runs this script to completion BEFORE starting the tailscale service, so
        # tailscaled isn't up yet here. Rename the node in the background: poll until the daemon
        # answers, set the hostname, exit. Backgrounding lets startup finish now (the job
        # reparents to nimi, which reaps but never kills it).
        ( for _ in $(seq 240); do
            tailscale status >/dev/null 2>&1 \
              && { tailscale set --hostname="''${TAILSCALE_HOSTNAME:-liszt}" --accept-dns=false || true; break; }
            sleep 0.5
          done ) &

        # git email routing, injected at runtime (agenix can't reach a throwaway host): default to GIT_EMAIL
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

            # Tailscale SSH (and the direct sshd fallback) start the login shell WITHOUT the
            # image's OCI Env, so PATH, the CA-cert vars (SSL_CERT_FILE/CURL_CA_BUNDLE), locale,
            # LD_LIBRARY_PATH, etc. are all missing. Re-import PID 1's (nimi's) environment, which
            # still carries the baked values, on every fish invocation. Uses only fish builtins so
            # it works from a bare shell (no coreutils on PATH yet).
            home.file.".config/fish/conf.d/00-liszt-env.fish".text = ''
              while read -lz __kv
                set -l pair (string split -m1 = -- $__kv)
                test (count $pair) -eq 2; and set -gx $pair[1] $pair[2] 2>/dev/null
              end < /proc/1/environ
            '';
          }
        ];
      };

      # System-wide CLI tools. Python/GPU work uses uv-managed interpreters, not this python3.
      # ollama is the CUDA build (cudaPkgs) so it offloads to the rented GPU.
      systemPackages = (with pkgs; [ uv tmux curl python3 htop ripgrep ]) ++ [ cudaPkgs.ollama-cuda ];

      exposedPorts = { "22/tcp" = { }; }; # direct sshd fallback; Tailscale SSH needs no ports
      registries = [ "ghcr.io/demic-dev" ]; # → ghcr.io/demic-dev/liszt
      tag = "latest";
    };
  };
}
