#!/usr/bin/env bash
# Builds .build/wm.app (daemon + CLI). SwiftPM cannot make app bundles, so this wraps its output.
# Usage: ./build-app.sh [debug|release]   (default: release)
# It stops a running wm just before it replaces the bundle, and starts the new build when it is done.
# NO_START=1 builds without starting it.
set -euo pipefail
cd "$(dirname "$0")"

configuration="${1:-release}"
swift build -c "$configuration"
bin="$(swift build -c "$configuration" --show-bin-path)"

app=".build/wm.app"

# The running daemon executes from the bundle, so it must stop before the bundle is deleted. `wm daemon stop` lets it put
# the windows back; if it does not exit in a few seconds it is killed.
if pgrep -x wmd >/dev/null; then
    echo "Stopping the running wm..."
    if [ -x "$app/Contents/MacOS/wm" ]; then "$app/Contents/MacOS/wm" daemon stop >/dev/null 2>&1 || true; fi
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x wmd >/dev/null || break; sleep 0.5; done
    if pgrep -x wmd >/dev/null; then pkill -x wmd || true; sleep 1; fi
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp bundle/Info.plist "$app/Contents/Info.plist"
# The Lua type stubs go in the bundle, so `wm lsp` can point editors at them (they must be here before the signing).
mkdir -p "$app/Contents/Resources/types"
cp types/wm.lua "$app/Contents/Resources/types/wm.lua"
cp "$bin/wmd" "$app/Contents/MacOS/wmd"
cp "$bin/wm" "$app/Contents/MacOS/wm"

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

codesign --force --sign "$identity" "$app/Contents/MacOS/wm"
codesign --force --sign "$identity" "$app"

requirement="$(codesign -dr - "$app" 2>&1 | grep 'designated =>' || true)"
case "$requirement" in
    *cdhash*) echo "signature: ad hoc (permissions reset on every build)" ;;
    *) echo "signature: stable ($requirement)" ;;
esac
echo "Built $app"

if [ -z "${NO_START:-}" ]; then
    "$app/Contents/MacOS/wm" daemon start
fi
