#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(cat VERSION)
build=$(cat BUILD_NUMBER)
swift build -c release --arch arm64 --arch x86_64
binary_dir=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
app="$PWD/dist/WavePlayer.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/AppIcon.iconset
cp "$binary_dir/WavePlayer" "$app/Contents/MacOS/WavePlayer"
for size in 16 32 128 256 512; do
 sips -z "$size" "$size" Assets/Icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
 double=$((size*2))
 sips -z "$double" "$double" Assets/Icon.png --out ".build/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns .build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c 'Print' Assets/Info.plist >/dev/null
cp Assets/Info.plist "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/WavePlayer-${version}-build${build}-macOS.zip"
