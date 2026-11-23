#!/usr/bin/env bash
# Releases wm: bumps Version.swift, commits, tags and pushes. The release workflow tests the tag and creates the GitHub release;
# the tap (g4rcez/homebrew-tap) follows that release by itself.
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
