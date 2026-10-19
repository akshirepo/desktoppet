#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/DesktopPet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DesktopPet "$APP/Contents/MacOS/DesktopPet"
cp -R Assets/Doodles "$APP/Contents/Resources/Doodles"
cp -R Assets/Sounds "$APP/Contents/Resources/Sounds"
cp -R Assets/Bubbles "$APP/Contents/Resources/Bubbles"
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for px in 16 32 128 256 512; do
  sips -z $px $px Assets/AppIcon/AppIcon-1024.png --out "$ICONSET/icon_${px}x${px}.png" >/dev/null
  sips -z $((px * 2)) $((px * 2)) Assets/AppIcon/AppIcon-1024.png --out "$ICONSET/icon_${px}x${px}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/Packs"
cp -R Assets/Packs/CorgiPack Assets/Packs/SheepPack "$APP/Contents/Resources/Packs/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.desktoppet</string>
  <key>CFBundleName</key><string>DesktopPet</string>
  <key>CFBundleExecutable</key><string>DesktopPet</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"
