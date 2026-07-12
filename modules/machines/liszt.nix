# liszt — ephemeral VastAI GPU container, joins the tailnet as `liszt` (see docs/liszt.md).
#
# Not a NixOS host: a Docker image built by CI (x86_64 only, .github/workflows/liszt-image.yml)
# on top of the official nvidia/cuda Ubuntu base, so VastAI's driver injection and
# manylinux wheels (torch/vLLM via uv) work out of the box, with our tools and
# home-manager config layered on top from nixpkgs.
{ inputs, config, ... }:
let
  homeModules = config.flake.homeModules;
in
{
  perSystem = { pkgs, lib, system, ... }: lib.mkIf (system == "x86_64-linux") (
    let
      hmCfg = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = with homeModules; [
          fish
          git
          {
            home.username = "root";
            home.homeDirectory = "/root";
            home.stateVersion = "26.05";
            home.packages = with pkgs; [ uv tmux curl python3 htop ripgrep ];
          }
        ];
      };
      # NOTE: must not be named `fish` — let bindings shadow `with homeModules;`
      # above, so a `fish` here would replace homeModules.fish in the modules
      # list with this package and make hmCfg depend on itself (infinite recursion).
      fishPkg = hmCfg.config.programs.fish.package;

      cudaBase = pkgs.dockerTools.pullImage {
        imageName = "nvidia/cuda";
        imageDigest = "sha256:520292dbb4f755fd360766059e62956e9379485d9e073bbd2f6e3c20c270ed66";
        finalImageName = "nvidia/cuda";
        finalImageTag = "12.8.1-devel-ubuntu24.04";
        hash = "sha256-eMo1+SfCjMh2zwXvfagw0v8QppUBdcJdhAct0f8MKlY=";
        # imageDigest = "sha256:ebef3c171eeef0298e4eb2e4be843105edf3b8b0ac45e0b43acee358e8046867";
        # finalImageName = "nvidia/cuda";
        # finalImageTag = "12.8.1-runtime-ubuntu24.04";
        os = "linux";
        arch = "amd64";
      };

      entrypoint = pkgs.writeShellScript "entrypoint" ''
        set -euo pipefail

        if [ -z "''${TAILSCALE_AUTHKEY:-}" ]; then
          echo "FATAL: TAILSCALE_AUTHKEY is unset. Set it in the VastAI template" >&2
          exit 1
        fi

        if [ -z "''${TAILSCALE_HOSTNAME:-}" ]; then
          echo "FATAL: TAILSCALE_HOSTNAME is unset. Set it in the VastAI template" >&2
          exit 1
        fi

        # Tailscale SSH spawns root's login shell from /etc/passwd. Point the shell
        # field at our fish at runtime: build-time extraCommands cannot edit files
        # owned by the base image, and replacing Ubuntu's passwd wholesale would
        # drop its system users.
        ${pkgs.gnused}/bin/sed -i "s|^\(root:.*:\)[^:]*$|\1${lib.getExe fishPkg}|" /etc/passwd

        mkdir -p /var/lib/tailscale /var/run/tailscale
        # env -u: keep the authkey out of tailscaled's environment, and therefore
        # out of every SSH session it spawns.
        env -u TAILSCALE_AUTHKEY ${pkgs.tailscale}/bin/tailscaled \
          --tun=userspace-networking \
          --statedir=/var/lib/tailscale \
          --socket=/var/run/tailscale/tailscaled.sock &

        for _ in $(${pkgs.coreutils}/bin/seq 60); do
          [ -S /var/run/tailscale/tailscaled.sock ] && break
          ${pkgs.coreutils}/bin/sleep 0.5
        done

        ${pkgs.tailscale}/bin/tailscale up \
          --authkey="''${TAILSCALE_AUTHKEY}" \
          --hostname="''${TAILSCALE_HOSTNAME}" \
          --ssh \
          --accept-dns=false

        echo "''${TAILSCALE_HOSTNAME} joined the tailnet — ssh root@''${TAILSCALE_HOSTNAME}"
        unset TAILSCALE_AUTHKEY
        unset TAILSCALE_HOSTNAME
        exec ${pkgs.coreutils}/bin/sleep infinity
      '';
    in
    {
      # streamLayeredImage over buildLayeredImage: the output is a script that streams the multi-GB tarball straight into `docker load`, so it never hits the nix store or the CI runner's disk twice.
      packages.liszt = pkgs.dockerTools.streamLayeredImage {
        name = "liszt";
        tag = "latest";
        fromImage = cudaBase;
        maxLayers = 60; # base layers count toward docker's 125-layer cap

        config = {
          Entrypoint = [ "${entrypoint}" ];
          WorkingDir = "/root";
          Env = [
            # Nix profile first so our fish/git/uv win; Ubuntu + CUDA paths after,
            # so nvidia-smi and runtime-injected driver tools still resolve.
            "PATH=/root/.nix-profile/bin:/usr/local/nvidia/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
            "HOME=/root"
            "USER=root"
            "LANG=C.UTF-8"
            "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            "CURL_CA_BUNDLE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
            "NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          ];
          Labels = {
            # Links the GHCR package to the repo so its visibility/permissions
            # can be managed from the repo settings.
            "org.opencontainers.image.source" = "https://github.com/demic-dev/configurations";
          };
        };

        # Bake the home-manager result statically instead of running its activation
        # script (which needs a nix profile/daemon the container doesn't have):
        # home-files is the finished symlink farm, home.path the buildEnv profile.
        # Interpolating the store paths pulls their closures into the image layers.
        extraCommands = ''
          mkdir -p root var/lib/tailscale
          cp -r ${hmCfg.activationPackage}/home-files/. root/
          chmod -R u+w root
          ln -s ${hmCfg.config.home.path} root/.nix-profile
        '';
      };
    }
  );
}
