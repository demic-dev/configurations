{ ... }:
{
  flake.nixosModules.satie =
    { env, ... }:
    {
      networking = {
        hostName = env.userSettings.satie.host;
        hostId = env.userSettings.satie.id;
        nameservers = env.userSettings.satie.network.nameservers;

        networkmanager = {
          enable = true;
          # Without this, NetworkManager pushes the DHCP-provided DNS servers into resolvconf alongside our static `nameservers` record above. `dns = "none"` stops NM from touching DNS.
          dns = "none";
          wifi.backend = "iwd";
          wifi.powersave = false;
          wifi.macAddress = "random";
        };

        firewall = rec {
          enable = true;
          allowedTCPPorts = [ 59520 ]; # Calibre wireless device connection
          allowedUDPPorts = allowedTCPPorts;
        };
      };
    };
}
