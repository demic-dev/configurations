{ ... }:
{
  flake.nixosModules.bach =
    { env, ... }:
    {
      networking = {
        hostName = env.userSettings.bach.host;
        hostId = env.userSettings.bach.id;
        nameservers = env.userSettings.bach.network.nameservers;

        networkmanager.enable = false;

        interfaces.enp7s0 = {
          useDHCP = false;
          ipv4.addresses = [{ address = env.userSettings.bach.network.ip.v4; prefixLength = 22; }];
          ipv6.addresses = [{ address = env.userSettings.bach.network.ip.v6; prefixLength = 64; }];
        };

        # Since the systemd stage-1 initrd migration, interface must be set
        # explicitly: nixpkgs only copies the default route into the initrd's
        # networkd config (40-enp7s0.network) when it is non-null, and without
        # it stage-1 SSH unlock is unreachable from outside the subnet.
        defaultGateway = {
          address = env.userSettings.bach.network.gateway;
          interface = "enp7s0";
        };
        firewall.enable = true;
      };
    };
}
