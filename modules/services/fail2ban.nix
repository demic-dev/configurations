{ ... }:
{
  flake.nixosModules.fail2ban =
{ conf, pkgs, ... }:
{
   services.fail2ban = {
    enable = true;

    maxretry = 5;
    bantime = "24h";
    bantime-increment = {
      enable = true;
      formula = "ban.Time * math.exp(float(ban.Count+1)*banFactor)/math.exp(1*banFactor)";
      maxtime = "168h";
      overalljails = true;
    };

    ignoreIP = [
      "100.64.0.0/10" # Tailscale
    ];
  };
}
  ;
}
