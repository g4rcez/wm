#!/usr/bin/env bash
# Builds .build/wm-<version>.dmg: a styled window (background, fixed size, icon places) with wm.app and a link to
# /Applications to drag it onto. Finder lays the window out through AppleScript, so macOS may ask once to let the terminal
# control Finder.
# Usage: scripts/make-dmg.sh   (CODESIGN_IDENTITY picks the certificate; without it build-app.sh signs ad hoc if it finds none)
set -euo pipefail
cd "$(dirname "$0")/.."

version="$(sed -n 's/.*wmVersion = "\(.*\)".*/\1/p' Sources/Common/Version.swift)"
volume="wm $version"
dmg=".build/wm-$version.dmg"
NO_START=1 NO_STOP=1 ./build-app.sh release

work="$(mktemp -d)"
mount="/Volumes/$volume"
cleanup() { hdiutil detach "$mount" -quiet -force 2>/dev/null || true; rm -rf "$work"; }
trap cleanup EXIT
hdiutil detach "$mount" -quiet -force 2>/dev/null || true

# The background: a 1x and a 2x picture in one TIFF, so it is sharp on a Retina screen and the same size on both.
mkdir -p "$work/stage/.background"
rsvg-convert -w 660 assets/dmg-background.svg -o "$work/bg.png"
rsvg-convert -w 1320 assets/dmg-background.svg -o "$work/bg@2x.png"
magick "$work/bg.png" -units PixelsPerInch -density 72 "$work/bg1.png"
magick "$work/bg@2x.png" -units PixelsPerInch -density 144 "$work/bg2.png"
tiffutil -cat "$work/bg1.png" "$work/bg2.png" -out "$work/stage/.background/background.tiff" 2>/dev/null

ditto .build/wm.app "$work/stage/wm.app"
ln -s /Applications "$work/stage/Applications"
cp bundle/wm.icns "$work/stage/.VolumeIcon.icns"

rw="$work/rw.dmg"
hdiutil create -quiet -volname "$volume" -srcfolder "$work/stage" -fs HFS+ -format UDRW -ov "$rw"
hdiutil attach -quiet -readwrite -noverify -noautoopen -mountpoint "$mount" "$rw"
command -v SetFile >/dev/null && SetFile -a C "$mount" || true

osascript <<OSA
tell application "Finder"
    tell disk "$volume"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 548}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to 112
        set text size of options to 13
        set background picture of options to file ".background:background.tiff"
        set position of item "wm.app" of container window to {180, 190}
        set position of item "Applications" of container window to {480, 190}
        update without registering applications
        delay 2
        close
    end tell
end tell
OSA

sync
hdiutil detach "$mount" -quiet
rm -f "$dmg"
hdiutil convert "$rw" -quiet -format UDZO -imagekey zlib-level=9 -o "$dmg"
echo "built $dmg"
