{ config, ... }:
{
  flake.nixosModules.bach =
    { env, inputs, ... }:
    {
      users.users.dhcpcd.uid = 997;
      users.groups.dhcpcd.gid = 997;

      users.users.mandb.uid = 980;
      users.groups.mandb.gid = 980;

      users.users.nscd.uid = 981;
      users.groups.nscd.gid = 981;

      users.users.systemd-oom.uid = 982;
      users.groups.systemd-oom.gid = 982;

      users.groups.resolvconf.gid = 983;
      users.groups.systemd-coredump.gid = 984;

      users.mutableUsers = false;
      users.users.root.initialHashedPassword = "$6$9joJdfYW9u7849iq$5jFEhesBUwM6yvSA8g8iMiog15pFTOIOEF28zzmgB2P1evUludMC0vboBsCFDylCvQWw6WFu8tc7VkhMjYKzr.";

      users.users.michele = {
        initialHashedPassword = "$6$DptngetaTDY6G.qa$tEWVAEGlpkvzUltZXYaZpQz4c40KOQG3eQXhwhcQn33oM02NyemgBFSa/G6Mzb9iKbTroI7uKd7AWgBfKuUGF.";
      };

      # agenix decrypts inside the pre-switch-root initrd activation — ~6s BEFORE
      # impermanence bind-mounts /persist/etc/ssh/ssh_host_ed25519_key onto /etc/ssh.
      age.identityPaths = [ "/persist${env.userSettings.bach.ssh.root.location}" ];

      age.secrets.git-email = {
        file = ../../../secrets/git-email.age;
        owner = env.userSettings.bach.user;
        group = "users";
      };
      age.secrets.noreply-github-email = {
        file = ../../../secrets/noreply-github-email.age;
        owner = env.userSettings.bach.user;
        group = "users";
      };

      age.secrets.michele-at-bach = {
        file = ../../../secrets/michele-at-bach.age;
        path = env.userSettings.bach.ssh.michele.location;
        owner = "michele";
        group = "users";
        mode = "600";
      };

      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.backupFileExtension = "bak";
      home-manager.extraSpecialArgs = { inherit env inputs; };
      home-manager.users.michele = {
        imports = with config.flake.homeModules; [ git fish ghostty ];

        home.username = "michele";
        # Must not have a trailing slash: home-manager's nixos module already derives this from
        # users.users.michele.home ("/home/michele"), and a mismatching value is a hard conflict.
        # (env...home.path keeps its trailing slash for the XDG_CONFIG_HOME concatenation below.)
        home.homeDirectory = "/home/michele";

        programs.neovim.enable = true;
        programs.neovim.withRuby = false;
        programs.neovim.withPython3 = false;

        home.sessionVariables = {
          EDITOR = "nvim";
          XDG_CONFIG_HOME = "${env.userSettings.bach.home.path}.config";
        };

        home.stateVersion = "23.05";
        programs.home-manager.enable = true;
      };
    };
}
