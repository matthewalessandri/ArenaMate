# Codex handoff: ArenaMate

You are working on a real SwiftUI macOS project. Preserve user assets and compact v4.6 design, and avoid large UI rewrites before the scanner is fixed.

## Critical outstanding bug
On the user's Mac, the app often says `Waiting for card...` despite Hearthstone showing three Arena draft choices. Previously, it also mapped a right-side hovered card into one of the three slots. A screenshot test recognized cards correctly, while live capture sometimes failed or lost permissions. Auto-class detection may also be inaccurate. Never claim capture is fixed unless a real macOS test verifies it.

## Required work
- Inspect `App/GameScreenOCR.swift`, `Shared/OfferRecognition.swift`, `App/DraftStore.swift`, `App/DraftOverlayController.swift` and the SwiftUI code.
- Add reproducible captured-frame fixtures and tests for normal Arena three-card offers and the special legendary-group selection screen.
- Separate live window capture, OCR, name matching and scoring into observable stages with safe diagnostic text.
- Correctly map left/middle/right by card position. Reject false readings from hovered cards or deck lists.
- Avoid repeated macOS permission requests; keep stable app ID and signing.
- Validate with Xcode on macOS, and preserve existing custom app icon and Innkeeper art.
- Sparkle integration and signed GitHub Release updates are implemented; follow `UPDATES.md` to configure the release keys and verify a real upgrade on macOS. Do not claim deployed updates work before that verification. Developer ID signing and notarization remain outstanding.

## Verification
- `swift test` passes.
- `xcodebuild -project ArenaMate.xcodeproj -scheme ArenaMate -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build` succeeds.
- A user can launch an installed `.app`, grant screen capture once, and see all three correctly positioned cards update promptly without manual screenshots.
- Opening Hearthstone while the app is running resumes detection. Closing the game shows a helpful retry state.
- GitHub Actions release DMG builds, launches, and is tested on a Mac before distribution.
