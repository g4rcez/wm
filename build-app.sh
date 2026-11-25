#!/usr/bin/env bash
# Builds .build/wm.app (daemon + CLI). SwiftPM cannot make app bundles, so this wraps its output.
# Usage: ./build-app.sh [debug|release]   (default: release)
# It stops a running wm just before it replaces the bundle, and starts the new build when it is done.
# NO_START=1 builds without starting it. NO_STOP=1 does not stop a running wm (the Homebrew formula builds in a temporary folder).
# STRIP=1 removes the debug symbols from the binaries (a release).
# SWIFT_BUILD_FLAGS adds flags to `swift build` (the formula passes --disable-sandbox).
set -euo pipefail
cd "$(dirname "$0")"

configuration="${1:-release}"
# shellcheck disable=SC2086  # the flags are split on purpose
swift build -c "$configuration" ${SWIFT_BUILD_FLAGS:-}
# shellcheck disable=SC2086
bin="$(swift build -c "$configuration" ${SWIFT_BUILD_FLAGS:-} --show-bin-path)"

app=".build/wm.app"
# The bundle is made in a staging folder and swapped in at the end, so a failed copy or signature leaves the old bundle (and the
# running wm) as they are.
staging=".build/wm.app.new"

rm -rf "$staging"
mkdir -p "$staging/Contents/MacOS"
cp bundle/Info.plist "$staging/Contents/Info.plist"
# The Lua type stubs go in the bundle, so `wm lsp` can point editors at them (they must be here before the signing).
mkdir -p "$staging/Contents/Resources/types"
cp types/wm.lua "$staging/Contents/Resources/types/wm.lua"
cp types/shortcuts.schema.json "$staging/Contents/Resources/types/shortcuts.schema.json"
# The app icon. assets/make-icns.sh makes it from assets/icon-windows.svg; this only copies it (before the signing).
cp bundle/wm.icns "$staging/Contents/Resources/wm.icns"
cp "$bin/wmd" "$staging/Contents/MacOS/wmd"
cp "$bin/wm" "$staging/Contents/MacOS/wm"

# macOS keeps the Accessibility and Screen Recording grants of an app by its "designated requirement". An ad-hoc
# signature makes that requirement the hash of this exact build, so every rebuild loses the grants. A real signing
# identity makes it "this bundle id, signed by this certificate", which does not change between builds.
#
# CODESIGN_IDENTITY (a certificate name or its SHA-1 hash) picks the identity; without it the first
# "Apple Development" certificate in the keychain is used; without that the signature is ad hoc.
identity="${CODESIGN_IDENTITY:-}"
if [ -z "$identity" ]; then
    identity="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ { print $2; exit }')"
fi
if [ -z "$identity" ]; then
    echo "warning: no code-signing identity found; signing ad hoc." >&2
    echo "         macOS will ask for Accessibility (and Screen Recording) again after every build." >&2
    identity="-"
fi

# The debug symbols name the folders of the machine that built the app: a release must not publish them. Before the signing.
if [ -n "${STRIP:-}" ]; then strip -S "$staging/Contents/MacOS/wm" "$staging/Contents/MacOS/wmd"; fi

codesign --force --sign "$identity" "$staging/Contents/MacOS/wm"
codesign --force --sign "$identity" "$staging"

requirement="$(codesign -dr - "$staging" 2>&1 | grep 'designated =>' || true)"
case "$requirement" in
    *cdhash*) echo "signature: ad hoc (permissions reset on every build)" ;;
    *) echo "signature: stable ($requirement)" ;;
esac

# The running daemon executes from the bundle, so it must stop before the bundle is replaced. `wm daemon stop` lets it put
# the windows back; if it does not exit in a few seconds it is killed.
if [ -z "${NO_STOP:-}" ] && pgrep -x wmd >/dev/null; then
    echo "Stopping the running wm..."
    if [ -x "$app/Contents/MacOS/wm" ]; then "$app/Contents/MacOS/wm" daemon stop >/dev/null 2>&1 || true; fi
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x wmd >/dev/null || break; sleep 0.5; done
    if pgrep -x wmd >/dev/null; then pkill -x wmd || true; sleep 1; fi
fi

rm -rf "$app"
mv "$staging" "$app"
echo "Built $app"

if [ -z "${NO_START:-}" ]; then
    "$app/Contents/MacOS/wm" daemon start
fi
