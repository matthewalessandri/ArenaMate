# ArenaMate for macOS

Native macOS Hearthstone Arena drafting companion. This is the current **v4.6-based prototype**, not a verified stable release; live card-detection issues are still under investigation.

## Development

- Open `ArenaMate.xcodeproj` in Xcode on a Mac to develop the app.
- Run `swift test` to exercise the portable recognition and scoring logic.
- Run `Build-Mac-App.command` for a local `.app` and `.dmg`.
- GitHub Actions (`.github/workflows/mac-build.yml`) builds and tests on a macOS runner on each push to `main`, and uploads an installable DMG as a workflow artifact.
- Publishing a stable GitHub Release with a `vMAJOR.MINOR.PATCH` tag builds a universal app and, once signing is configured, attaches the DMG, signed update ZIP, and signed Sparkle feed. See [Automatic updates](UPDATES.md) for one-time setup and verification.

**Current release limitations:** The GitHub CI output uses ad-hoc signing and is NOT notarized by Apple. It can prompt Gatekeeper warnings and macOS screen-recording permissions. Sparkle checks for updates with user consent and verifies signed feeds and archives. Release builds require the update signing key described in [UPDATES.md](UPDATES.md). Developer ID signing and notarization remain outstanding; ad-hoc app signing can cause screen-recording permission prompts after replacement. Do not place signing private keys in the repository.

## Roadmap for Codex

1. Fix capture and OCR against actual Hearthstone screenshots, including legendary groups, avoiding false positions from sidebars and hover cards.
2. Establish stable bundle signing, permissions and diagnostic reporting without flooding users with permission prompts.
3. Preserve the compact interface while fixing automated detection.
4. Validate the Sparkle update flow on a Mac, then replace ad-hoc CI signing with Developer ID / notarization for public distribution.

See `CODEX_HANDOFF.md` for actionable acceptance criteria.
