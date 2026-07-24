 set -e
# $3 == 1 => branch checkout (what `git clone` triggers). Skip file checkouts so the
# `git checkout -- .` below does not re-enter this hook.
[ "$3" = "1" ] || exit 0
root="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -f "$root/.gitattributes" ] || exit 0
grep -q 'filter=git-agecrypt' "$root/.gitattributes" || exit 0
command -v git-agecrypt >/dev/null 2>&1 || exit 0

git config --get filter.git-agecrypt.smudge >/dev/null 2>&1 || git-agecrypt init
if [ -f "$HOME/.ssh/git-agecrypt_ed25519" ]; then
    git config git-agecrypt.config.identity "$HOME/.ssh/git-agecrypt_ed25519"
elif [ -f "$HOME/.ssh/id_ed25519" ]; then
    git config git-agecrypt.config.identity "$HOME/.ssh/id_ed25519"
fi
# Force the now-registered smudge filter to run on the already-checked-out ciphertext.
git -C "$root" checkout -- . 2>/dev/null || true