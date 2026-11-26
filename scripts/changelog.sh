#!/usr/bin/env bash
# The Unreleased section of CHANGELOG.md, for a release.
#   scripts/changelog.sh check <file>             fails unless Unreleased has at least one entry
#   scripts/changelog.sh notes <file>             prints the entries of Unreleased (the release notes)
#   scripts/changelog.sh stamp <file> <version>   renames Unreleased to the version and today, with a new empty Unreleased above
set -euo pipefail

mode="${1:-}"
file="${2:-}"
[ -f "$file" ] || { echo "error: no changelog at '$file'" >&2; exit 1; }

notes() {
    awk '/^## Unreleased[[:space:]]*$/ { inside = 1; next } /^## / { inside = 0 } inside' "$file"
}

case "$mode" in
check)
    notes | grep -q '^- ' || { echo "error: the Unreleased section of $file has no entry: say what changed for users" >&2; exit 1; }
    ;;
notes)
    notes | sed -e '/./,$!d'
    ;;
stamp)
    version="${3:-}"
    [ -n "$version" ] || { echo "error: stamp needs a version" >&2; exit 1; }
    today="$(date +%Y-%m-%d)"
    tmp="$(mktemp)"
    awk -v heading="## $version - $today" '
        !done && /^## Unreleased[[:space:]]*$/ { print "## Unreleased"; print ""; print heading; done = 1; next }
        { print }' "$file" > "$tmp"
    mv "$tmp" "$file"
    ;;
*)
    echo "usage: scripts/changelog.sh check|notes|stamp <file> [version]" >&2
    exit 2
    ;;
esac
