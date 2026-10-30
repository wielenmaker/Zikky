#!/bin/sh
# Builds dist/Zikky.app and dist/Zikky-<version>.zip (ad-hoc signed).
# Usage: scripts/bundle.sh [version]
set -eu
cd "$(dirname "$0")/.."
version=${1:-0.0.1}
app=dist/Zikky.app

zig build -Doptimize=ReleaseFast
rm -rf dist
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp zig-out/bin/zikky "$app/Contents/MacOS/"
cp assets/Zikky.icns "$app/Contents/Resources/"
cat > "$app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key><string>zikky</string>
	<key>CFBundleIdentifier</key><string>dev.zikky.editor</string>
	<key>CFBundleName</key><string>Zikky</string>
	<key>CFBundleDisplayName</key><string>Zikky</string>
	<key>CFBundleIconFile</key><string>Zikky</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$version</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$app"
ditto -c -k --keepParent "$app" "dist/Zikky-$version.zip"
