#!/usr/bin/env bash
# Asserts that a release archive is safe to publish. brew installs this file, so the checks read the archive and not the build
# folder. release.sh runs it before it publishes.
#
#   scripts/verify-release.sh <wm-version-macos.tar.gz>
#
# It fails unless:
#   - wm.app has exactly the designated requirement of scripts/designated-requirement, so that macOS keeps the permissions of
#     the users through the upgrade;
#   - the signature is intact, Apple notarized the app and the ticket is stapled to it;
#   - the archive names no user, home folder or computer of this Mac.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
die() { echo "error: $*" >&2; exit 1; }

archive="${1:-}"
[ -f "$archive" ] || { echo "usage: scripts/verify-release.sh <archive.tar.gz>" >&2; exit 2; }
pinned="$(cat "$repo/scripts/designated-requirement")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
tar -C "$work" -xzf "$archive"
app="$work/wm.app"
[ -d "$app" ] || die "no wm.app in the archive"

requirement="$(codesign -dr - "$app" 2>/dev/null | sed -n 's/^designated => //p')"
[ "$requirement" = "$pinned" ] || die "another designated requirement: every user would have to grant the permissions again
  pinned: $pinned
  app:    ${requirement:-none}"
codesign --verify --deep --strict -R "=$pinned" "$app" || die "the signature is broken or does not satisfy the requirement"
xcrun stapler validate "$app" >/dev/null || die "no notarization ticket is stapled to the app"
assessment="$(spctl --assess --type execute --verbose "$app" 2>&1)" || die "Gatekeeper rejects the app: $assessment"
grep -qxF "source=Notarized Developer ID" <<<"$assessment" || die "Gatekeeper does not see a notarized app: $assessment"
# With the assessments switched off, spctl accepts everything and says so.
! grep -q "^override=" <<<"$assessment" || die "Gatekeeper is switched off on this Mac: $assessment"

owners="$(tar -tvzf "$archive" | awk '{ print $3 ":" $4 }' | sort -u)"
[ "$owners" = "root:wheel" ] || die "the archive names the owners of its files: $owners"
# grep reads a file, not a pipe: with pipefail, a pipe that grep -q closes early hides the match.
gzip -dc "$archive" > "$work/stream.tar"
for private in "$HOME/" "$(id -un)" "$(scutil --get LocalHostName 2>/dev/null || true)" "$(scutil --get ComputerName 2>/dev/null || true)"; do
    [ -n "$private" ] || continue
    ! LC_ALL=C grep -qaF -- "$private" "$work/stream.tar" || die "the archive contains \"$private\""
done

echo "verified: $(basename "$archive") is notarized, keeps the permissions and names nothing of this Mac"
