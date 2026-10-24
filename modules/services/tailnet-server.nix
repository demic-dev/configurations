{ ... }:
{
  flake.nixosModules.tailnet-server =
    { config, ... }:
    {
      networking.firewall = {
        enable = true;

        trustedInterfaces = [ "tailscale0" ];

        allowedUDPPorts = [ config.services.tailscale.port ];
      };

      # Limit SSH to Tailscale's interface
      services.openssh.listenAddresses = [
        {
          addr = "100.99.26.16";
          port = 22;
        }
      ];

      # SSH requires tailscale to run first
      systemd.services."sshd" = {
        requires = [ "tailscaled.service" ];
        after = [ "tailscaled.service" ];
      };
    };
}
