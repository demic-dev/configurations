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

    # liszt (VastAI GPU container) input. Builds CUDA from its own pinned nixpkgs, so it is
    # intentionally NOT `nixpkgs.follows` — that would break its binary cache hits.
    nix2gpu.url = "github:fleek-sh/nix2gpu/0.1.0";

    # satie (Apple-Silicon laptop) inputs
    nixos-apple-silicon = {
      url = "github:nix-community/nixos-apple-silicon";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      # url = "github:youwen5/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
    firefox-addons = {
      url = "gitlab:rycee/nur-expressions?dir=pkgs/firefox-addons";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dms = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dank-greeter = {
      url = "github:AvengeMedia/dank-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dgop = {
      url = "github:AvengeMedia/dgop";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dms-plugin-registry = {
      url = "github:AvengeMedia/dms-plugin-registry";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    danksearch = {
      url = "github:AvengeMedia/danksearch";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    gruvbox-wallpapers = {
      url = "github:AngelJumbo/gruvbox-wallpapers";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  nixConfig = rec {
    trusted-public-keys = [
      "nixos-apple-silicon.cachix.org-1:8psDu5SA5dAD7qA0zMy5UT292TxeEPzIz8VVEr2Js20="
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    ];
    substituters = [
      "https://nixos-apple-silicon.cachix.org"
      "https://cache.nixos.org"
    ];
    trusted-substituters = substituters;
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      # x86_64-linux exists only for the liszt VastAI container image (modules/machines/liszt.nix).
      systems = [ "aarch64-linux" "x86_64-linux" ];
      imports =
        # home-manager's flakeModule exposes flake.homeModules.<name>; nix2gpu's adds
        # perSystem.nix2gpu.<name> for building GPU container images (modules/machines/liszt.nix).
        [
          inputs.home-manager.flakeModules.default
          inputs.nix2gpu.flakeModule
        ]
        # Every .nix under ./modules is auto-imported as a flake-parts module.
        ++ (inputs.import-tree ./modules).imports;
    };
}
