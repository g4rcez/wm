#!/usr/bin/env bash
# Releases wm from this Mac: tests, bumps Version.swift, builds a universal wm.app signed with the release certificate, then
# commits, tags, pushes, creates the GitHub release with the app attached and writes Formula/wm.rb of the Homebrew tap
# (g4rcez/homebrew-tap) from scripts/wm.rb.in. It uses your own keychain, `gh` login and git access: CI holds no secret.
#
#   scripts/release.sh patch|minor|major|X.Y.Z [--dry-run]
#
# The certificate comes from scripts/make-signing-cert.sh; scripts/signing-cert.sha1 pins it.
set -euo pipefail

cd "$(dirname "$0")/.."

usage() { echo "usage: scripts/release.sh patch|minor|major|X.Y.Z [--dry-run]" >&2; exit 2; }
die() { echo "error: $*" >&2; exit 1; }

bump="${1:-}"; [ -n "$bump" ] || usage
dry=0; [ "${2:-}" = "--dry-run" ] && dry=1
file=Sources/Common/Version.swift

[ "$(git branch --show-current)" = "main" ] || die "release from main"
[ -z "$(git status --porcelain)" ] || die "the working tree is not clean"
git fetch --quiet origin main --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || die "main is not in sync with origin/main"

# The same certificate for every release, or macOS asks every user for the permissions again.
identity="$(tr -d '[:space:]' < scripts/signing-cert.sha1 2>/dev/null || true)"
[[ "$identity" =~ ^[0-9A-F]{40}$ ]] || die "no certificate pinned in scripts/signing-cert.sha1: run scripts/make-signing-cert.sh"
security find-identity -p codesigning | grep -q "$identity" \
    || die "the release certificate $identity is not in your keychain: import its backup (see the development docs)"
gh auth status >/dev/null 2>&1 || die "gh is not logged in: run gh auth login"

current="$(sed -n 's/.*wmVersion = "\(.*\)".*/\1/p' "$file")"
[ -n "$current" ] || die "no wmVersion in $file"
IFS=. read -r major minor patch <<<"$current"

case "$bump" in
  patch) next="$major.$minor.$((patch + 1))" ;;
  minor) next="$major.$((minor + 1)).0" ;;
  major) next="$((major + 1)).0.0" ;;
  *) [[ "$bump" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage; next="$bump" ;;
esac
tag="v$next"

git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists"
[ "$(printf '%s\n%s\n' "$current" "$next" | sort -V | tail -1)" = "$next" ] && [ "$current" != "$next" ] \
  || die "$next is not newer than $current"

echo "release: $current -> $next ($tag)"
[ "$dry" = 1 ] && { echo "dry run: nothing changed"; exit 0; }

# Tests that hang must not hold the terminal.
timeout_cmd="$(command -v timeout || command -v gtimeout || true)"
${timeout_cmd:+$timeout_cmd 600} swift test

# Until the commit, a failure puts the version back.
work="$(mktemp -d)"
committed=0
cleanup() { [ "$committed" = 1 ] || git checkout --quiet -- "$file"; rm -rf "$work"; }
trap cleanup EXIT

sed -i '' "s/wmVersion = \"$current\"/wmVersion = \"$next\"/" "$file"

# A universal binary: the package supports Intel Macs too.
CODESIGN_IDENTITY="$identity" STRIP=1 NO_START=1 NO_STOP=1 SWIFT_BUILD_FLAGS="--arch arm64 --arch x86_64" ./build-app.sh release

app=.build/wm.app
requirement="$(codesign -dr - "$app" 2>&1 | grep 'designated =>')"
echo "$requirement"
echo "$requirement" | grep -qi "H\"$identity\"" || die "the signature does not name the release certificate"
codesign --verify --deep --strict "$app"
for arch in arm64 x86_64; do
    lipo "$app/Contents/MacOS/wmd" -verify_arch "$arch" || die "the app has no $arch slice"
done
[ "$("$app/Contents/MacOS/wm" --version)" = "wm $next" ] || die "the built app is not version $next"

# The asset is public: no folder of this machine goes in it.
if cat "$app/Contents/MacOS/"* | LC_ALL=C grep -qaF "$HOME/"; then die "the binaries name folders under your home"; fi

asset="wm-$next-macos.tar.gz"
mkdir "$work/pack"
ditto "$app" "$work/pack/wm.app"
cp LICENSE "$work/pack/"
COPYFILE_DISABLE=1 tar -C "$work/pack" -czf "$work/$asset" wm.app LICENSE
sha="$(shasum -a 256 "$work/$asset" | cut -d' ' -f1)"
echo "$sha" > "$work/$asset.sha256"

git add "$file"
git commit -m "chore(release): $tag" -m "- Bump the version so \`wm version\` matches the tag and the app of the release."
committed=1
git tag -a "$tag" -m "wm $next"
git push origin main "$tag"

gh release create "$tag" "$work/$asset" "$work/$asset.sha256" --title "wm $next" --generate-notes --verify-tag

url="https://github.com/g4rcez/wm/releases/download/$tag/$asset"
git clone --quiet git@github.com:g4rcez/homebrew-tap.git "$work/tap"
sed -e "s#@URL@#$url#" -e "s#@SHA256@#$sha#" scripts/wm.rb.in > "$work/tap/Formula/wm.rb"
git -C "$work/tap" add Formula/wm.rb
git -C "$work/tap" commit --quiet -m "wm $next"
git -C "$work/tap" push --quiet origin HEAD:main
echo "tap: Formula/wm.rb is at $next; run: brew update && brew upgrade g4rcez/tap/wm"
