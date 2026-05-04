#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MetaFetch"
APP_VERSION="${APP_VERSION:-1.1}"
APP_BUILD="${APP_BUILD:-2}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:--}"
APP_NOTARY_PROFILE="${APP_NOTARY_PROFILE:-}"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
DMG_PATH="$RELEASE_DIR/$APP_NAME-$APP_VERSION.dmg"

export APP_VERSION
export APP_BUILD
export APP_SIGN_IDENTITY

"$ROOT_DIR/Scripts/build_app.sh"

mkdir -p "$RELEASE_DIR"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"

hdiutil create \
  -volname "$APP_NAME $APP_VERSION" \
  -srcfolder "$APP_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [ "$APP_SIGN_IDENTITY" != "-" ]; then
  codesign --force --timestamp --sign "$APP_SIGN_IDENTITY" "$DMG_PATH" >/dev/null
  echo "Signed DMG with identity: $APP_SIGN_IDENTITY"
else
  echo "Warning: DMG is not Developer ID signed because APP_SIGN_IDENTITY was not set."
fi

if [ -n "$APP_NOTARY_PROFILE" ]; then
  if [ "$APP_SIGN_IDENTITY" = "-" ]; then
    echo "Error: APP_NOTARY_PROFILE requires APP_SIGN_IDENTITY to be set." >&2
    exit 1
  fi

  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$APP_NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  echo "Notarized and stapled DMG."
fi

shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
echo "Built release DMG at: $DMG_PATH"
echo "Wrote SHA-256 checksum at: $DMG_PATH.sha256"
