{ ... }:
{
  flake.homeModules.nvim =
    { config, pkgs, inputs, ... }:
    {
      home.packages = [
        pkgs.neovim
        # lowPrio: this ships git, gcc and nodejs, which other modules also install.
        (pkgs.lib.lowPrio inputs.nvim.packages.${pkgs.stdenv.hostPlatform.system}.default)
      ];

      # Out of store: vim.pack writes its lock file next to the config, which a store symlink
      # would make read-only.
      xdg.configFile."nvim".source =
        config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/repos/nvim";
    };
}
