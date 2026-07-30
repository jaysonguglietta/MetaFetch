#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MetaFetch"
APP_VERSION="${APP_VERSION:-2.02}"
APP_BUILD="${APP_BUILD:-5}"
APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-}"
APP_NOTARY_PROFILE="${APP_NOTARY_PROFILE:-}"
REPOSITORY="${GITHUB_REPOSITORY:-jaysonguglietta/MetaFetch}"
RELEASE_NOTES_FILE="${RELEASE_NOTES_FILE:-$ROOT_DIR/Documentation/ReleaseNotes-$APP_VERSION.md}"
TAG="v$APP_VERSION"
DMG_PATH="$ROOT_DIR/dist/release/$APP_NAME-$APP_VERSION.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"

fail() {
  echo "Error: $1" >&2
  exit 1
}

[[ "$APP_VERSION" =~ '^[0-9]+([.][0-9]+){1,2}$' ]] ||
  fail "APP_VERSION must be a numeric release version such as 2.02."
[[ "$APP_BUILD" =~ '^[1-9][0-9]*$' ]] ||
  fail "APP_BUILD must be a positive integer."
[[ "$APP_SIGN_IDENTITY" == Developer\ ID\ Application:* ]] ||
  fail "APP_SIGN_IDENTITY must be a Developer ID Application identity."
[ -n "$APP_NOTARY_PROFILE" ] ||
  fail "APP_NOTARY_PROFILE must name a notarytool keychain profile."
[ -f "$RELEASE_NOTES_FILE" ] ||
  fail "Release notes were not found at $RELEASE_NOTES_FILE."

command -v gh >/dev/null 2>&1 || fail "GitHub CLI (gh) is required."
gh auth status >/dev/null

CURRENT_BRANCH="$(git -C "$ROOT_DIR" branch --show-current)"
[ "$CURRENT_BRANCH" = "main" ] ||
  fail "Production releases must be published from main, not $CURRENT_BRANCH."
[ -z "$(git -C "$ROOT_DIR" status --porcelain)" ] ||
  fail "Commit or remove all working-tree changes before publishing."

git -C "$ROOT_DIR" fetch origin main
LOCAL_SHA="$(git -C "$ROOT_DIR" rev-parse HEAD)"
REMOTE_SHA="$(git -C "$ROOT_DIR" rev-parse origin/main)"
[ "$LOCAL_SHA" = "$REMOTE_SHA" ] ||
  fail "Local main must exactly match origin/main before publishing."

security find-identity -v -p codesigning |
  grep -F "\"$APP_SIGN_IDENTITY\"" >/dev/null ||
  fail "The requested Developer ID identity is not available in Keychain."

xcrun notarytool history \
  --keychain-profile "$APP_NOTARY_PROFILE" \
  --output-format json >/dev/null

if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
  fail "GitHub Release $TAG already exists."
fi

APP_VERSION="$APP_VERSION" \
APP_BUILD="$APP_BUILD" \
APP_SIGN_IDENTITY="$APP_SIGN_IDENTITY" \
APP_NOTARY_PROFILE="$APP_NOTARY_PROFILE" \
  "$ROOT_DIR/Scripts/build_release_dmg.sh"

codesign --verify --verbose=2 "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature -vv "$DMG_PATH"
shasum -a 256 -c "$CHECKSUM_PATH"

gh release create "$TAG" \
  "$DMG_PATH" \
  "$CHECKSUM_PATH" \
  --repo "$REPOSITORY" \
  --target "$LOCAL_SHA" \
  --title "$APP_NAME $APP_VERSION" \
  --notes-file "$RELEASE_NOTES_FILE" \
  --latest

gh release view "$TAG" --repo "$REPOSITORY"
