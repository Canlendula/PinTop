#!/bin/zsh
# Builds TopPin.app (universal: arm64 + x86_64) into ./build
set -euo pipefail
cd "${0:A:h}"

APP=build/TopPin.app
MODCACHE=build/.modcache
mkdir -p build "$MODCACHE"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SOURCES=(Sources/TopPin/*.swift)
FLAGS=(-O -swift-version 5 -module-cache-path "$MODCACHE" -module-name TopPin
       -framework AppKit -framework ScreenCaptureKit -framework CoreMedia
       -framework Carbon -framework ServiceManagement)

if [[ -z "${ARCHS:-}" ]]; then
  TARGET_ARCHS=(arm64)
else
  TARGET_ARCHS=($=ARCHS)
fi
BINS=()
for arch in "${TARGET_ARCHS[@]}"; do
  echo "→ compiling $arch"
  swiftc "${FLAGS[@]}" -target "${arch}-apple-macos14.0" "${SOURCES[@]}" -o "build/TopPin-$arch"
  BINS+=("build/TopPin-$arch")
done
lipo -create $BINS -output "$APP/Contents/MacOS/TopPin"
rm -f $BINS

cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# Sign with a stable identity if one is available (keeps privacy permissions across rebuilds),
# otherwise ad-hoc.
IDENTITY=${SIGN_IDENTITY:--}
codesign --force --deep --options runtime --sign "$IDENTITY" "$APP"
echo "✓ built $APP"
