#!/usr/bin/env bash
# Makes bundle/wm.icns from assets/icon-windows.svg. build-app.sh only copies the result, so run this when the SVG changes.
# Needs rsvg-convert (librsvg), magick (ImageMagick) and iconutil (part of macOS).
set -euo pipefail
cd "$(dirname "$0")/.."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
iconset="$tmp/wm.iconset"
mkdir "$iconset"

# macOS app icons are 824 points wide in a 1024 canvas. The margin holds a soft shadow.
rsvg-convert -w 824 -h 824 assets/icon-windows.svg -o "$tmp/art.png"
magick -size 1024x1024 xc:none -gravity center \
    \( "$tmp/art.png" -background black -shadow 45x18+0+0 \) -geometry +0+14 -composite \
    "$tmp/art.png" -composite "$tmp/master.png"

# name, pixels
for entry in icon_16x16:16 icon_16x16@2x:32 icon_32x32:32 icon_32x32@2x:64 icon_128x128:128 icon_128x128@2x:256 \
    icon_256x256:256 icon_256x256@2x:512 icon_512x512:512 icon_512x512@2x:1024; do
    magick "$tmp/master.png" -resize "${entry#*:}x${entry#*:}" "$iconset/${entry%%:*}.png"
done

iconutil -c icns "$iconset" -o bundle/wm.icns
echo "Made bundle/wm.icns"
