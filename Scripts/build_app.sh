#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MetaFetch"
ICON_NAME="metafetch-app-icon"
APP_VERSION="${APP_VERSION:-2.01}"
APP_BUILD="${APP_BUILD:-4}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:--}"
SPARKLE_FEED_URL="${SPARKLE_FEED_URL:-}"
SPARKLE_PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-}"
BUILD_DIR="$ROOT_DIR/.build"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
EXECUTABLE_PATH="$BUILD_DIR/debug/$APP_NAME"
SPARKLE_FRAMEWORK_PATH="$BUILD_DIR/debug/Sparkle.framework"

mkdir -p "$ROOT_DIR/dist"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
CLANG_MODULE_CACHE_PATH=/tmp/metafetch-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/metafetch-swiftpm-cache \
swift build

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$FRAMEWORKS_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [ ! -d "$SPARKLE_FRAMEWORK_PATH" ]; then
  echo "Error: Sparkle.framework was not produced by SwiftPM." >&2
  exit 1
fi
cp -R "$SPARKLE_FRAMEWORK_PATH" "$FRAMEWORKS_DIR/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME"

if [ -f "$ROOT_DIR/Branding/metafetch-logo.svg" ]; then
  cp "$ROOT_DIR/Branding/metafetch-logo.svg" "$RESOURCES_DIR/metafetch-logo.svg"
fi

if [ -f "$ROOT_DIR/Branding/$ICON_NAME.icns" ]; then
  cp "$ROOT_DIR/Branding/$ICON_NAME.icns" "$RESOURCES_DIR/$ICON_NAME.icns"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MetaFetch</string>
    <key>CFBundleIconFile</key>
    <string>metafetch-app-icon</string>
    <key>CFBundleIdentifier</key>
    <string>com.jaysonguglietta.metafetch</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MetaFetch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSQuitAlwaysKeepsWindows</key>
    <false/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

if [ -n "$SPARKLE_FEED_URL" ] || [ -n "$SPARKLE_PUBLIC_KEY" ]; then
  if [[ "$SPARKLE_FEED_URL" != https://* ]] || [ -z "$SPARKLE_PUBLIC_KEY" ]; then
    echo "Error: signed updates require an HTTPS SPARKLE_FEED_URL and SPARKLE_PUBLIC_KEY." >&2
    exit 1
  fi
  plutil -insert SUFeedURL -string "$SPARKLE_FEED_URL" "$CONTENTS_DIR/Info.plist"
  plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_KEY" "$CONTENTS_DIR/Info.plist"
  plutil -insert SUEnableAutomaticChecks -bool false "$CONTENTS_DIR/Info.plist"
  plutil -insert SURequireSignedFeed -bool true "$CONTENTS_DIR/Info.plist"
  plutil -insert SUVerifyUpdateBeforeExtraction -bool true "$CONTENTS_DIR/Info.plist"
fi

if command -v codesign >/dev/null 2>&1; then
  if [ "$APP_SIGN_IDENTITY" = "-" ]; then
    # Ad-hoc signatures do not share a stable Team ID with Sparkle's nested code,
    # so hardened library validation would reject the local development build.
    # Distribution builds below retain hardened runtime and library validation.
    codesign --force --deep \
      --preserve-metadata=identifier,entitlements,flags \
      --sign - "$FRAMEWORKS_DIR/Sparkle.framework" >/dev/null
    codesign --force --deep --entitlements "$ROOT_DIR/MetaFetch.entitlements" --sign - "$APP_DIR" >/dev/null
    echo "Ad-hoc signed local app bundle. Use APP_SIGN_IDENTITY for hardened distribution builds."
  else
    codesign --force --deep --timestamp --options runtime \
      --preserve-metadata=identifier,entitlements,flags \
      --sign "$APP_SIGN_IDENTITY" "$FRAMEWORKS_DIR/Sparkle.framework" >/dev/null
    codesign --force --deep --timestamp --options runtime --entitlements "$ROOT_DIR/MetaFetch.entitlements" --sign "$APP_SIGN_IDENTITY" "$APP_DIR" >/dev/null
    echo "Signed app bundle with identity: $APP_SIGN_IDENTITY"
  fi
else
  echo "Warning: codesign was not found; app bundle is unsigned."
fi

"$ROOT_DIR/Scripts/verify_app_bundle.sh" "$APP_DIR"

echo "Built app bundle at: $APP_DIR"
