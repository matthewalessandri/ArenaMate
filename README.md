# ArenaMate for macOS

Native macOS Hearthstone Arena drafting companion. This is the current **v4.6-based prototype**, not a verified stable release; live card-detection issues are still under investigation.

## Development

- Open `ArenaMate.xcodeproj` in Xcode on a Mac to develop the app.
- Run `swift test` to exercise the portable recognition and scoring logic.
- Run `Build-Mac-App.command` for a local `.app` and `.dmg`.
- GitHub Actions (`.github/workflows/mac-build.yml`) builds and tests on a macOS runner on each push to `main`, and uploads an installable DMG as a workflow artifact.
- Publishing a GitHub Release triggers the same workflow and attaches the DMG to that release. Inspect the build logs for success before sharing it.

**Current release limitations:** The GitHub CI output uses ad-hoc signing and is NOT notarized by Apple. It can prompt Gatekeeper warnings and macOS screen-recording permissions. This workflow does not create a secure automatic in-app updater. Reliable unattended updates require a permanent signing identity and appropriately signed update artifacts (e.g. Sparkle + its update signing keys). Do not place signing private keys in the repository.

## Roadmap for Codex

1. Fix capture and OCR against actual Hearthstone screenshots, including legendary groups, avoiding false positions from sidebars and hover cards.
2. Establish stable bundle signing, permissions and diagnostic reporting without flooding users with permission prompts.
3. Preserve the compact interface while fixing automated detection.
4. Implement a signed update feed and release flow (Sparkle recommended), then replace ad-hoc CI signing with Developer ID / notarization for public distribution.

See `CODEX_HANDOFF.md` for actionable acceptance criteria.
