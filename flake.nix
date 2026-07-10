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

    # nix2gpu: builds the declarative CUDA + Tailscale container image we run on
    # VastAI GPU instances (see modules/gpu/vastai.nix, docs/vastai-gpu.md).
    # NOTE: deliberately do NOT `follows` nixpkgs here — nix2gpu builds the
    # container with its OWN pinned, cuda-enabled nixpkgs, and overriding it
    # would swap out the tested CUDA package set under the image.
    nix2gpu = {
      url = "github:fleek-sh/nix2gpu";
      inputs.flake-parts.follows = "flake-parts";
    };

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
      # nix2gpu upstream cache + CUDA cache, so building the GPU image is mostly
      # downloads rather than multi-hour local CUDA compiles.
      "weyl-ai.cachix.org-1:cR0SpSAPw7wejZ21ep4SLojE77gp5F2os260eEWqTTw="
      "cuda-maintainers.cachix.org-1:0dq3bujKpuEPMCX6U4WylrUDZ9JyUG0VpVZa7CNfq5E="
    ];
    substituters = [
      "https://nixos-apple-silicon.cachix.org"
      "https://cache.nixos.org"
      "https://weyl-ai.cachix.org"
      "https://cuda-maintainers.cachix.org"
    ];
    trusted-substituters = substituters;
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      # aarch64-linux: the real fleet (satie laptop, bach VPS).
      # x86_64-linux: only used to evaluate/build the nix2gpu VastAI GPU image
      # (modules/gpu/vastai.nix); no nixosConfiguration targets it.
      systems = [ "aarch64-linux" "x86_64-linux" ];
      imports =
        # home-manager's flakeModule exposes flake.homeModules.<name> for aspects to register into.
        [ inputs.home-manager.flakeModules.default inputs.nix2gpu.flakeModule ]
        # Every .nix under ./modules is auto-imported as a flake-parts module.
        ++ (inputs.import-tree ./modules).imports;
    };
}
