#!/bin/bash
# Accretion: builds AccretionAppleID.framework (arm64 iOS) into AppleIDBridge/build/ for `make`.
# Needs macOS with Xcode and rustup. The framework is linked by Feather.xcconfig and copied into
# Accretion.app/Frameworks by the Makefile.
set -euo pipefail
cd "$(dirname "$0")"

# Our one change to Impactor (anisette v3 server URL, remote only). Applied once; skipped if already in.
if ! git -C Impactor apply --reverse --check ../patches/omnisette-remote-v3.patch 2>/dev/null; then
	git -C Impactor apply ../patches/omnisette-remote-v3.patch
fi

rustup target add aarch64-apple-ios >/dev/null
export IPHONEOS_DEPLOYMENT_TARGET=16.0
cargo build --release --locked --target aarch64-apple-ios

OUT=build/AccretionAppleID.framework
rm -rf "$OUT"
mkdir -p "$OUT"
cp target/aarch64-apple-ios/release/libaccretion_appleid.dylib "$OUT/AccretionAppleID"
install_name_tool -id @rpath/AccretionAppleID.framework/AccretionAppleID "$OUT/AccretionAppleID"
cat > "$OUT/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>AccretionAppleID</string>
	<key>CFBundleIdentifier</key>
	<string>io.github.getaccretion.Accretion.AppleID</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>AccretionAppleID</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>iPhoneOS</string>
	</array>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>MinimumOSVersion</key>
	<string>16.0</string>
</dict>
</plist>
PLIST
echo "Built $OUT ($(du -h "$OUT/AccretionAppleID" | cut -f1))"
