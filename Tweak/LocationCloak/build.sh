#!/bin/bash
#
# Build LocationCloak.dylib cho iOS arm64
#
# Yêu cầu: Xcode + iOS SDK
#
# Output: LocationCloak.dylib
#

set -e

SDK=$(xcrun --sdk iphoneos --show-sdk-path)
CC=$(xcrun --find clang)
CODESIGN=$(xcrun --find codesign)

echo "[*] Building LocationCloak.dylib..."

$CC -arch arm64 \
    -isysroot "$SDK" \
    -shared \
    -framework Foundation \
    -framework CoreLocation \
    -fobjc-arc \
    -miphoneos-version-min=15.0 \
    -o LocationCloak.dylib \
    LocationCloak.m

echo "[*] Signing..."
$CODESIGN --force --sign - --timestamp=none LocationCloak.dylib

echo "[*] Verifying..."
file LocationCloak.dylib
otool -L LocationCloak.dylib | head -5

echo ""
echo "[✓] LocationCloak.dylib ready."
echo ""
echo "Cài đặt:"
echo ""
echo "  TrollStore:"
echo "    1. Copy LocationCloak.dylib vào /var/jb/usr/lib/TweakInject/"
echo "    2. Tạo file /var/jb/usr/lib/TweakInject/LocationCloak.plist:"
echo "       { Filter = { Bundles = ( \"com.apple.springboard\" ); }; }"
echo "    3. Respring"
echo ""
echo "  Jailbreak (Substrate/ElleKit):"
echo "    1. Copy LocationCloak.dylib vào /Library/MobileSubstrate/DynamicLibraries/"
echo "    2. Tạo LocationCloak.plist cạnh file .dylib"
echo "    3. Respring hoặc ldrestart"
echo ""
echo "  Dopamine:"
echo "    1. Copy vào /var/jb/Library/MobileSubstrate/DynamicLibraries/"
echo "    2. Respring"
