#!/usr/bin/env fish
#
# Add a new git-agecrypt "sensitive" value: a value committed encrypted but read as cleartext
# from the working tree at eval time (see ../../env.nix). The script registers the file and its
# recipients in ../../git-agecrypt.toml via `git-agecrypt config add`, writes the cleartext, and
# stages it so git-agecrypt's clean filter encrypts what actually gets committed.
#
# Just run it and answer the prompts.

set -l repo_root (git rev-parse --show-toplevel 2>/dev/null)
if test -z "$repo_root"
    echo "Not inside a git repository." >&2
    exit 1
end
cd $repo_root; or exit 1

read -l -P "Name of the new sensitive value (filename without .age): " name
if test -z "$name"
    echo "A name is required." >&2
    exit 1
end

set -l rel "../secrets/sensitive/$name.age"
if test -e "$rel"
    echo "Warning: $rel already exists." >&2
else
    # Write the effective (cleartext) value.
    echo "Enter the value to store in $rel, then press Ctrl-D:"
    cat >$rel
end

# Collect one or more recipient public keys (age recipients or ssh public keys).
set -l recipients
echo "Enter recipient public key(s). Submit an empty line when done."
while true
    set -l n (math (count $recipients) + 1)
    read -l -P "  public key #$n (empty to finish): " key
    if test -z "$key"
        break
    end
    set -a recipients $key
end
if test (count $recipients) -eq 0
    echo "At least one public key is required." >&2
    exit 1
end

# Register the file + recipients in git-agecrypt.toml.
set -l rflags
for key in $recipients
    set -a rflags -r $key
end
git-agecrypt config add $rflags -p "$rel"; or exit 1

# Stage it: git-agecrypt's clean filter encrypts the committed blob to the recipients above.
git add "$rel"

echo
echo "Done: $rel registered for "(count $recipients)" recipient(s) and staged (encrypted on commit)."

