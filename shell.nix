{ pkgs ? import <nixpkgs> { } }:
pkgs.mkShell {
  MOTD = ''
    scripts/add-sensitive.fish   add a git-agecrypt value
    scripts/rekey.fish           re-encrypt the agenix secrets a key can read
  '';
}
