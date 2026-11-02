#!/bin/zsh
# Build, sign, notarize and publish a RuckusAdmin release, and update the Sparkle appcast.
#
#   scripts/release.sh 1.0.1 "What changed"
#
# Steps: Release archive → Developer ID export → notarize and staple (when a notarytool keychain
# profile exists) → zip → EdDSA signature (key in your login Keychain, made by Sparkle's
# generate_keys) → GitHub release carrying the zip → appcast.xml updated, committed and pushed.
# The app's SUFeedURL points at appcast.xml on the main branch, so running apps see the new
# version at their next hourly check (or immediately via RuckusAdmin ▸ Check for Updates…).
#
# One-time notarization setup (asks for an app-specific password from appleid.apple.com):
#   xcrun notarytool store-credentials RuckusAdmin --apple-id you@example.com --team-id HCJTB3TKCY
#
# Environment: REPO (owner/name, default spotdgtl/RuckusAdmin), NOTARY_PROFILE (default RuckusAdmin),
# ALLOW_UNNOTARIZED=1 to publish without notarization.
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION=${1:?usage: scripts/release.sh <version> [release notes]}
NOTES=${2:-"RuckusAdmin $VERSION"}
REPO=${REPO:-spotdgtl/RuckusAdmin}
NOTARY_PROFILE=${NOTARY_PROFILE:-RuckusAdmin}
TAG="v$VERSION"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: commit or stash your changes first; the release is tagged from HEAD" >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  echo "error: tag $TAG already exists" >&2
  exit 1
fi

BUILD_NUMBER=$(git rev-list --count HEAD)
BUILD_DIR=build
DERIVED="$BUILD_DIR/DerivedData"
ARCHIVE="$BUILD_DIR/RuckusAdmin.xcarchive"
EXPORT="$BUILD_DIR/export"
APP="$EXPORT/RuckusAdmin.app"
ZIP_NAME="RuckusAdmin-$VERSION.zip"
ZIP="$BUILD_DIR/$ZIP_NAME"
mkdir -p "$BUILD_DIR"
rm -rf "$ARCHIVE" "$EXPORT" "$ZIP"

echo "==> Archiving RuckusAdmin $VERSION (build $BUILD_NUMBER)"
xcodebuild -project RuckusAdmin.xcodeproj -scheme RuckusAdmin -configuration Release \
  -derivedDataPath "$DERIVED" -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  archive -quiet

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$EXPORT" -quiet
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Notarizing"
ditto -c -k --keepParent "$APP" "$ZIP"
NOTARIZED=0
if xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait; then
  xcrun stapler staple "$APP"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  NOTARIZED=1
elif [[ "${ALLOW_UNNOTARIZED:-0}" == "1" ]]; then
  echo "warning: not notarized; continuing because ALLOW_UNNOTARIZED=1" >&2
else
  echo "error: notarization failed. One-time setup:" >&2
  echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <apple id> --team-id HCJTB3TKCY" >&2
  exit 1
fi
spctl --assess --type execute --verbose=2 "$APP" || true

echo "==> Signing the update for Sparkle"
SIGN_UPDATE=$(find "$DERIVED/SourcePackages/artifacts" -path '*/bin/sign_update' -type f | head -1)
SIGNATURE=$("$SIGN_UPDATE" "$ZIP")

echo "==> Publishing GitHub release $TAG"
git tag -a "$TAG" -m "RuckusAdmin $VERSION"
git push origin "$TAG"
gh release create "$TAG" "$ZIP" --repo "$REPO" --title "RuckusAdmin $VERSION" --notes "$NOTES"

echo "==> Updating appcast.xml"
python3 scripts/appcast.py appcast.xml \
  --version "$BUILD_NUMBER" --short-version "$VERSION" \
  --url "https://github.com/$REPO/releases/download/$TAG/$ZIP_NAME" \
  --signature "$SIGNATURE" --notes "$NOTES" \
  --release-page "https://github.com/$REPO/releases/tag/$TAG" --minimum-system-version 15.0
git add appcast.xml
git commit -q -m "Publish $VERSION to the appcast"
git push -q origin HEAD

if [[ $NOTARIZED == 1 ]]; then STATUS=notarized; else STATUS="NOT notarized"; fi
echo "Done: RuckusAdmin $VERSION (build $BUILD_NUMBER), $STATUS. App: $APP"
