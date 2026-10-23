#!/usr/bin/env bash
set -euo pipefail
# Called by CI from the repository root. Keep signing material in stdin only.
: "${SPARKLE_PUBLIC_ED_KEY:?Missing public key}"
: "${SPARKLE_PRIVATE_ED_KEY:?Missing signing key}"
: "${SOURCE_PACKAGES:?Missing resolved package directory}"
: "${DOWNLOAD_PREFIX:?Missing release download URL}"
: "${BUILD_VERSION:?Missing app build version}"
appcast_tool=$(find "$SOURCE_PACKAGES/artifacts" -type f -path '*/bin/generate_appcast' -print)
if [[ ! -x "$appcast_tool" || "$appcast_tool" == *$'\n'* ]]; then
  echo 'Expected exactly one generate_appcast tool from the pinned Sparkle package.' >&2
  exit 1
fi
printf '%s\n' "$SPARKLE_PRIVATE_ED_KEY" | "$appcast_tool" \
  --ed-key-file - --maximum-deltas 0 \
  --download-url-prefix "$DOWNLOAD_PREFIX" -o dist/appcast.xml dist/updates
signature=$(python3 Scripts/validate_appcast.py dist/appcast.xml dist/updates/ArenaMate-update.zip \
  "$BUILD_VERSION" "${DOWNLOAD_PREFIX}ArenaMate-update.zip")
xcrun swift Scripts/verify-update.swift "$SPARKLE_PUBLIC_ED_KEY" "$signature" dist/updates/ArenaMate-update.zip
# Verify the feed signature too; this does not modify the signed file.
sign_tool="$(dirname "$appcast_tool")/sign_update"
printf '%s\n' "$SPARKLE_PRIVATE_ED_KEY" | "$sign_tool" --ed-key-file - --verify dist/appcast.xml
