#!/bin/zsh

set -euo pipefail

APP_DIR="${1:-dist/MetaFetch.app}"
EXECUTABLE="$APP_DIR/Contents/MacOS/MetaFetch"
FRAMEWORK="$APP_DIR/Contents/Frameworks/Sparkle.framework"
SPARKLE_BINARY="$FRAMEWORK/Versions/B/Sparkle"
INFO_PLIST="$APP_DIR/Contents/Info.plist"

fail() {
  echo "Bundle verification failed: $1" >&2
  exit 1
}

[ -f "$INFO_PLIST" ] || fail "Info.plist is missing."
[ -x "$EXECUTABLE" ] || fail "MetaFetch executable is missing or not executable."
[ -d "$FRAMEWORK" ] || fail "Sparkle.framework is not embedded."
[ -x "$SPARKLE_BINARY" ] || fail "The embedded Sparkle binary is missing or not executable."

BUNDLE_IDENTIFIER="$(plutil -extract CFBundleIdentifier raw "$INFO_PLIST")"
[ "$BUNDLE_IDENTIFIER" = "com.jaysonguglietta.metafetch" ] || fail "Unexpected bundle identifier: $BUNDLE_IDENTIFIER"

otool -L "$EXECUTABLE" | grep -Fq '@rpath/Sparkle.framework/Versions/B/Sparkle' || \
  fail "MetaFetch is not linked to the expected embedded Sparkle framework."
otool -l "$EXECUTABLE" | grep -Fq '@executable_path/../Frameworks' || \
  fail "MetaFetch is missing the embedded-framework runtime search path."

if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict --verbose=2 "$APP_DIR"
fi

echo "Verified embedded frameworks, runtime paths, bundle identity, and code signatures: $APP_DIR"
