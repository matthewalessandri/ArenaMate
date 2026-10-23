#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")"

failure() {
  echo ''
  echo 'Build did not complete. See build.log in this folder.'
  if [[ -f build.log ]]; then tail -n 25 build.log; fi
  echo 'You can close this window.'
  read '?Press Return to close…' || true
}
trap failure ERR

if ! xcodebuild -version >/dev/null 2>&1; then
  echo 'This ONE-TIME BUILD requires full Xcode. Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer'
  echo 'Once installed, ArenaMate runs independently without Xcode or Terminal.'
  read '?Press Return to close…' || true
  exit 1
fi

if pgrep -x ArenaMate >/dev/null 2>&1; then
  echo 'Quit the running ArenaMate (Cmd-Q), then run this installer again.'
  read '?Press Return to close…' || true
  exit 1
fi

# Retain the same bundle identifier and install path across builds, which helps
# macOS track a single app rather than a new downloaded instance each release.
IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development:|"Mac Developer:|"Developer ID Application:/{print $2; exit}' || true)"
if [[ -n "$IDENTITY" ]]; then
  SIGN_ARGS=(CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$IDENTITY")
  echo "Signing using: $IDENTITY"
else
  SIGN_ARGS=(CODE_SIGNING_ALLOWED=YES 'CODE_SIGN_IDENTITY=-')
  echo 'Using ad-hoc signing. macOS may require screen permission again after a rebuilt version.'
  echo 'A free Apple Development certificate configured in Xcode improves permission persistence.'
fi

mkdir -p dist
xcodebuild -project ArenaMate.xcodeproj -scheme ArenaMate -configuration Release -destination 'platform=macOS' \
   -clonedSourcePackagesDirPath "$(pwd)/.SourcePackages" -onlyUsePackageVersionsFromResolvedFile \
   -derivedDataPath "$(pwd)/.DerivedData" \
   "SPARKLE_PUBLIC_ED_KEY=${SPARKLE_PUBLIC_ED_KEY:-}" "${SIGN_ARGS[@]}" build > build.log 2>&1 || { tail -n 60 build.log; false; }
APP="$(pwd)/.DerivedData/Build/Products/Release/ArenaMate.app"
if [[ ! -d "$APP" ]]; then echo 'ArenaMate.app was not created.'; false; fi

INSTALL="$HOME/Applications/ArenaMate.app"
mkdir -p "$HOME/Applications"
rm -rf "$INSTALL"
ditto "$APP" "$INSTALL"

# Portable DMG, built locally without uploading files or paying for hosting.
# macOS Finder can install it with drag-and-drop, no development tools needed.
STAGING="$(mktemp -d "${TMPDIR:-/tmp/}arenamate.XXXXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$STAGING"
ditto "$INSTALL" "$STAGING/ArenaMate.app"
ln -s /Applications "$STAGING/Applications"
rm -f dist/ArenaMate.dmg
hdiutil create -quiet -ov -volname 'ArenaMate' -srcfolder "$STAGING" -format UDZO 'dist/ArenaMate.dmg'

# A stable standalone app stays in ~/Applications, independent of this builder folder.
echo ''
echo 'SUCCESS — ArenaMate is a standalone Mac app.'
echo "Installed: $INSTALL"
echo "Optional drag-and-drop installer: $(pwd)/dist/ArenaMate.dmg"
echo 'Launch it from ~/Applications or Spotlight. No Terminal or Xcode needed to run it.'
open "$INSTALL"
read '?Press Return to close…' || true
