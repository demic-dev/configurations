#!/usr/bin/env fish
#
# Rekey only the agenix secrets this user's ssh key can actually decrypt — i.e. the entries in
# secrets.nix whose recipients include the given public key. Secrets encrypted only to another
# host's keys are skipped (agenix can't decrypt them, so a plain `agenix --rekey` would fail on
# them). The git-agecrypt files under ./sensitive/ are not agenix secrets and are untouched.
#
# Usage: ./scripts/rekey.fish [path/to/ssh_public_key]     (default: ~/.ssh/id_ed25519.pub)

# This script lives in scripts/ but operates on the sibling secrets/ dir — secrets.nix and
# the *.age files live there — so resolve that relative to the script's own location,
# independent of the caller's cwd.
cd (dirname (status filename))/../secrets; or exit 1

set -l pubkey_file $argv[1]
if test -z "$pubkey_file"
    set pubkey_file "$HOME/.ssh/id_ed25519.pub"
end
if not test -f "$pubkey_file"
    echo "Public key not found: $pubkey_file" >&2
    exit 1
end

# Keep only "type base64" (drop the trailing comment) so it matches the keys in secrets.nix.
set -l pubkey (awk '{ print $1 " " $2 }' "$pubkey_file")
set -l secrets_nix (pwd)/secrets.nix

# A filtered agenix rules file: same recipients as secrets.nix, but only the entries that list
# this key. Copied verbatim, so each file is still re-encrypted to its full recipient set.
set -l rules (mktemp)
set -l expr 'let
  orig = import @SECRETS@;
  # Normalize a key to "type base64", ignoring any comment, before comparing.
  normalize = k:
    let m = builtins.match "([^ ]+) ([^ ]+).*" k;
    in if m == null then k else "${builtins.elemAt m 0} ${builtins.elemAt m 1}";
  key = normalize "@PUBKEY@";
  hasKey = v: builtins.any (k: normalize k == key) v.publicKeys;
in builtins.listToAttrs
     (map (n: { name = n; value = orig.${n}; })
       (builtins.filter (n: hasKey orig.${n}) (builtins.attrNames orig)))'
string replace -a '@SECRETS@' $secrets_nix -- $expr \
    | string replace -a '@PUBKEY@' $pubkey >$rules

set -l count (nix-instantiate --eval -E "builtins.length (builtins.attrNames (import $rules))")
if test "$count" -eq 0
    echo "No secret in secrets.nix is encrypted to $pubkey_file — nothing to rekey."
    rm -f $rules
    exit 0
end

echo "Rekeying $count secret(s) decryptable by $pubkey_file:"
nix-instantiate --eval --json -E "builtins.attrNames (import $rules)" | tr -d '[]"' | tr ',' '\n' | sed 's/^/  /'

env RULES="$rules" agenix --rekey
rm -f $rules
