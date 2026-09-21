
{ ... }:
let
  bekkoEmbeddingUrl = "https://huggingface.co/hotchpotch/bekko-embedding-v1-a8m-GGUF/resolve/4acacdea60b9393ae247a6ebf5b5707938c9755b/bekko-embedding-v1-a8m-Q8_0.gguf";
in
{
  flake.nixosModules.llama-cpp =
    { pkgs, ... }:
    {
      services.llama-cpp = {
        enable = true;

        settings = {
          model = pkgs.fetchurl {
            url = bekkoEmbeddingUrl;
            hash = "sha256-CwIUIUKH6Q/7mP+0fhBx5bGT+0INHZmy7IqrDrtQf8A=";
          };
          threads = 4;
          embeddings = true;
        };
      };
    };
}
