{
  description = "NixOS configuration for my machines";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix.url = "github:ryantm/agenix";
    impermanence.url = "github:nix-community/impermanence";

    nixos-apple-silicon = {
      url = "github:nix-community/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      # url = "github:youwen5/zen-browser-flake";
      inputs = {
        # Temporary: the nixpkgs satie runs, so the deployed builds are reused (no disk space).
        nixpkgs.url = "github:nixos/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";
        home-manager.follows = "home-manager";
      };
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.url = "github:nixos/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";
    };
    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.url = "github:nixos/nixpkgs/f20cd90e28fe0403873f473b29e42662cd86e8c4";
    };
    fastpotify = {
      url = "github:crmne/fastpotify";
      # Otherwise it links an older glibc than the system's Mesa needs, and EGL fails to load.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    hister = {
      url = "github:asciimoo/hister";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nvim = {
      url = "github:demic-dev/nvim";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    poco = {
      url = "github:demic-dev/poco";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "aarch64-linux" ];
      imports =
        # home-manager's flakeModule exposes flake.homeModules.<name> for aspects to register into.
        [ inputs.home-manager.flakeModules.default ]
        # Every .nix under ./modules is auto-imported as a flake-parts module.
        ++ [ (inputs.import-tree ./modules) ];
      perSystem = { pkgs, ... }: {
        devShells.default = import ./shell.nix { inherit pkgs; };
      };
    };
}
