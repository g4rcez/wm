#!/usr/bin/env bash
# Releases wm: bumps Version.swift, commits, tags and pushes, then bumps Formula/wm.rb in the Homebrew tap
# (g4rcez/homebrew-tap) with your own git access. The release workflow tests the tag and creates the GitHub release.
#
#   scripts/release.sh patch|minor|major|X.Y.Z [--dry-run]
set -euo pipefail

cd "$(dirname "$0")/.."

usage() { echo "usage: scripts/release.sh patch|minor|major|X.Y.Z [--dry-run]" >&2; exit 2; }

bump="${1:-}"; [ -n "$bump" ] || usage
dry=0; [ "${2:-}" = "--dry-run" ] && dry=1
file=Sources/Common/Version.swift

[ "$(git branch --show-current)" = "main" ] || { echo "error: release from main" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "error: the working tree is not clean" >&2; exit 1; }
git fetch --quiet origin main --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "error: main is not in sync with origin/main" >&2; exit 1; }

current="$(sed -n 's/.*wmVersion = "\(.*\)".*/\1/p' "$file")"
[ -n "$current" ] || { echo "error: no wmVersion in $file" >&2; exit 1; }
IFS=. read -r major minor patch <<<"$current"

case "$bump" in
  patch) next="$major.$minor.$((patch + 1))" ;;
  minor) next="$major.$((minor + 1)).0" ;;
  major) next="$((major + 1)).0.0" ;;
  *) [[ "$bump" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || usage; next="$bump" ;;
esac
tag="v$next"

git rev-parse -q --verify "refs/tags/$tag" >/dev/null && { echo "error: tag $tag already exists" >&2; exit 1; }
[ "$(printf '%s\n%s\n' "$current" "$next" | sort -V | tail -1)" = "$next" ] && [ "$current" != "$next" ] \
  || { echo "error: $next is not newer than $current" >&2; exit 1; }

echo "release: $current -> $next ($tag)"
[ "$dry" = 1 ] && { echo "dry run: nothing changed"; exit 0; }

# Tests that hang must not hold the terminal.
timeout_cmd="$(command -v timeout || command -v gtimeout || true)"
${timeout_cmd:+$timeout_cmd 600} swift test

sed -i '' "s/wmVersion = \"$current\"/wmVersion = \"$next\"/" "$file" 2>/dev/null \
  || sed -i "s/wmVersion = \"$current\"/wmVersion = \"$next\"/" "$file"
git add "$file"
git commit -m "chore(release): $tag" -m "- Bump the version so \`wm version\` matches the tag the release workflow builds."
git tag -a "$tag" -m "wm $next"
git push origin main "$tag"

echo "pushed $tag: follow the release at https://github.com/g4rcez/wm/actions"

# The tap: the archive of the tag is what the formula builds. GitHub makes it a moment after the push.
url="https://github.com/g4rcez/wm/archive/refs/tags/$tag.tar.gz"
sha=""
for _ in 1 2 3 4 5 6 7 8 9 10; do
  sha="$(curl -fsSL "$url" | shasum -a 256 | cut -d' ' -f1)" && [ "$sha" != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ] && break
  sha=""; sleep 3
done
[ -n "$sha" ] || { echo "error: cannot read $url; bump the tap by hand" >&2; exit 1; }

tap="$(mktemp -d)"
trap 'rm -rf "$tap"' EXIT
git clone --quiet git@github.com:g4rcez/homebrew-tap.git "$tap"
sed -i '' -e "s#^  url \".*\"#  url \"$url\"#" -e "s#^  sha256 \".*\"#  sha256 \"$sha\"#" "$tap/Formula/wm.rb"
git -C "$tap" add Formula/wm.rb
git -C "$tap" commit --quiet -m "wm $next"
git -C "$tap" push --quiet origin HEAD:main
echo "tap: Formula/wm.rb is at $next; run: brew upgrade g4rcez/tap/wm"
