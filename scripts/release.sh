#!/usr/bin/env bash
# Releases wm from this Mac: tests, bumps Version.swift, builds a universal wm.app signed with a Developer ID certificate,
# has Apple notarize it, then commits, tags, pushes, creates the GitHub release with the app attached and writes
# Formula/wm.rb of the Homebrew tap (g4rcez/homebrew-tap) from scripts/wm.rb.in. It uses your own keychain, `gh` login and
# git access: CI holds no secret.
#
#   scripts/release.sh patch|minor|major|X.Y.Z [--dry-run]
#
# It needs, once on this Mac (see "Releases and signing" in the development docs):
#   - a "Developer ID Application" certificate in the keychain, of the team that scripts/signing-team-id names;
#   - notarytool credentials in the keychain profile `wm-notary` (NOTARY_PROFILE picks another).
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

# The same team for every release, or macOS asks every user for the permissions again. A renewed certificate of the same team
# keeps them, so the pin is the team and not one certificate.
team="$(tr -d '[:space:]' < scripts/signing-team-id 2>/dev/null || true)"
[[ "$team" =~ ^[A-Z0-9]{10}$ ]] || die "no team pinned: write your Team ID to scripts/signing-team-id and commit it"
identity="$(scripts/signing-identity.sh --release)"
[ -n "$identity" ] \
    || die "no \"Developer ID Application\" certificate of team $team in your keychain (see the development docs)"
notary_profile="${NOTARY_PROFILE:-wm-notary}"
xcrun notarytool history --keychain-profile "$notary_profile" >/dev/null 2>&1 \
    || die "notarytool cannot use the keychain profile $notary_profile: run xcrun notarytool store-credentials $notary_profile"
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
CODESIGN_IDENTITY="$identity" TIMESTAMP=1 STRIP=1 NO_START=1 NO_STOP=1 SWIFT_BUILD_FLAGS="--arch arm64 --arch x86_64" \
    ./build-app.sh release

app=.build/wm.app
codesign -dr - "$app" 2>&1 | grep 'designated =>'
codesign --verify --deep --strict "$app"
codesign --verify -R "=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
and certificate leaf[subject.OU] = \"$team\"" "$app" || die "the signature is not a Developer ID signature of team $team"
for arch in arm64 x86_64; do
    lipo "$app/Contents/MacOS/wmd" -verify_arch "$arch" || die "the app has no $arch slice"
done
[ "$("$app/Contents/MacOS/wm" --version)" = "wm $next" ] || die "the built app is not version $next"

# The asset is public: no folder of this machine goes in it.
if cat "$app/Contents/MacOS/"* | LC_ALL=C grep -qaF "$HOME/"; then die "the binaries name folders under your home"; fi

# Apple checks the app and issues a ticket; stapling puts it in the bundle, so Gatekeeper accepts the app without the network.
ditto -c -k --keepParent "$app" "$work/notarize.zip"
echo "notarizing (this takes a few minutes)..."
xcrun notarytool submit "$work/notarize.zip" --keychain-profile "$notary_profile" --wait --timeout 30m \
    --output-format json > "$work/notary.json" || true
status="$(plutil -extract status raw -o - "$work/notary.json" 2>/dev/null || true)"
if [ "$status" != "Accepted" ]; then
    cat "$work/notary.json" >&2
    submission="$(plutil -extract id raw -o - "$work/notary.json" 2>/dev/null || true)"
    [ -z "$submission" ] || xcrun notarytool log "$submission" --keychain-profile "$notary_profile" >&2 || true
    die "Apple did not accept the app (status: ${status:-unknown})"
fi
xcrun stapler staple "$app"
spctl --assess --type execute --verbose "$app"

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
