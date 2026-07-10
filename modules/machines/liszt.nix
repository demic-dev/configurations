# liszt — declarative GPU container image for VastAI, built with nix2gpu.
#
# Not a NixOS host (unlike bach/satie): it's a `perSystem` container-image output
# we push to GHCR and run on rented, ephemeral VastAI GPU instances. Named after
# the virtuoso pianist — muscular, summoned for a burst of performance, then gone.
#
# Why this exists: renting an ephemeral GPU box on VastAI used to mean redoing
# the whole SSH-key -> clone -> .env -> run dance by hand, against an IP/port
# that changes every time. Instead we bake a reproducible CUDA + Tailscale image
# once, push it to GHCR, and use it as a VastAI template. On boot the container
# joins our tailnet under the stable name `liszt`, so `ssh root@liszt` always
# works (MagicDNS + Tailscale SSH) regardless of the instance's ephemeral address.
#
# See docs/liszt.md for the end-to-end runbook.
#
# IMPORTANT constraints baked into this file:
#   * nixpkgs CUDA is x86_64-linux only, and our real fleet is aarch64, so the
#     image is only ever defined for x86_64-linux (guarded below). It cannot be
#     built on the laptop/VPS — CI (.github/workflows/liszt-image.yml) or an
#     x86_64 remote builder produces it.
#   * The container is evaluated with nix2gpu's OWN cuda-enabled nixpkgs (the
#     `pkgs` passed into this module), not this flake's nixpkgs.
{ ... }:
{
  perSystem =
    { system, lib, ... }:
    {
      # Guard to x86_64 only: nix2gpu evaluates its perSystem for x86_64-linux
      # exclusively, so defining `nix2gpu.liszt` for aarch64 would try to build a
      # container that does not exist and error out.
      nix2gpu = lib.optionalAttrs (system == "x86_64-linux") {
        liszt =
          { pkgs, lib, ... }:
          let
            # Reuse our existing public keys instead of duplicating them. Only the
            # (non-secret) michele pubkeys are read here; the lazy `cloudSettings`
            # age reads in env.nix are never forced, so this stays CI-safe even
            # when the git-agecrypt secrets are still ciphertext.
            env = import ../../env.nix { inherit (pkgs) lib; };
            authorizedKeys = [
              env.userSettings.satie.ssh.michele.value
              env.userSettings.bach.ssh.michele.value
            ];

            # nix2gpu's stock tailscale service runs `tailscale up --ssh` but does
            # NOT set a hostname, so the tailnet/MagicDNS name would be random and
            # `ssh root@liszt` would not resolve. We override the service argv to add
            # a stable `--hostname` (overridable at runtime via $TAILSCALE_HOSTNAME).
            #
            # Userspace networking is required: VastAI containers do not guarantee
            # /dev/net/tun or NET_ADMIN. `--accept-dns=false` keeps the container's
            # own DNS (needed for git clone / uv) intact — we only need the node to
            # be reachable by name from our other tailnet members, not to consume
            # MagicDNS itself.
            tailscaleService = pkgs.writeShellApplication {
              name = "nix2gpu-vastai-tailscale";
              runtimeInputs = [ pkgs.tailscale ];
              # `--hostname="''${TAILSCALE_HOSTNAME:-liszt}"`: In case of multiple hosts summoned, the latter's hostname, `liszt`, would take place of the former.
              text = ''
                mkdir -p /var/lib/tailscale /var/run/tailscale

                tailscaled \
                  --tun=userspace-networking \
                  --socket=/var/run/tailscale/tailscaled.sock &
                daemon_pid=$!

                if [ -n "''${TAILSCALE_AUTHKEY:-}" ]; then
                  sleep 3
                  tailscale up \
                    --authkey="$TAILSCALE_AUTHKEY" \
                    --ssh \
                    --hostname="''${TAILSCALE_HOSTNAME:-liszt}" \
                    --accept-dns=false
                else
                  echo "[nix2gpu/vastai] TAILSCALE_AUTHKEY not set; skipping 'tailscale up'." >&2
                fi

                wait "$daemon_pid"
              '';
            };
          in
          {
            # Pushed to by `nix run .#liszt.copyToGithub` (see CI). Image ref becomes
            # ghcr.io/demic-dev/liszt:latest (name defaults to the attr name "liszt").
            registries = [ "ghcr.io/demic-dev" ];

            # Tools the base dev environment does not already ship but we need to
            # land, clone, and run the pipeline. (git in particular is missing from
            # nix2gpu's default dev set.)
            systemPackages = with pkgs; [
              git
              openssh
              cacert
            ];

            # Tailscale SSH is the primary access path; these baked public keys are
            # a fallback for VastAI's direct/proxy SSH port if Tailscale is down.
            # Read at runtime by nix2gpu's startup script into /root/.ssh/authorized_keys.
            extraEnv.SSH_PUBLIC_KEYS = lib.concatStringsSep "\n" authorizedKeys;

            tailscale.enable = true;
            services.tailscale.process.argv = lib.mkForce [ (lib.getExe tailscaleService) ];
          };
      };
    };
}
