# ArenaMate for macOS

Native macOS Hearthstone Arena drafting companion. This is the current **v4.6-based prototype**, not a verified stable release; live card-detection issues are still under investigation.

## Development

- Open `ArenaMate.xcodeproj` in Xcode on a Mac to develop the app.
- Run `swift test` to exercise the portable recognition and scoring logic.
- Run `Build-Mac-App.command` for a local `.app` and `.dmg`.
- GitHub Actions (`.github/workflows/mac-build.yml`) builds and tests on a macOS runner on each push to `main`, and uploads an installable DMG as a workflow artifact.
- Publishing a stable GitHub Release with a `vMAJOR.MINOR.PATCH` tag builds a universal app and, once signing is configured, attaches the DMG, signed update ZIP, and signed Sparkle feed. See [Automatic updates](UPDATES.md) for one-time setup and verification.

**Current release limitations:** The GitHub CI output uses ad-hoc signing and is NOT notarized by Apple. It can prompt Gatekeeper warnings and macOS screen-recording permissions. Sparkle checks for updates with user consent and verifies signed feeds and archives. Release builds require the update signing key described in [UPDATES.md](UPDATES.md). Developer ID signing and notarization remain outstanding; ad-hoc app signing can cause screen-recording permission prompts after replacement. Do not place signing private keys in the repository.

## Draft ratings

ArenaMate refreshes the free HSReplay Arena card-statistics feed at most twice a day and caches it locally. It turns class-specific drawn win rates into relative ratings, shrinks low-sample results toward the class average, and then applies the local deck-need and verified-synergy adjustments. If the feed is unavailable, the last cache remains active; without a cache, ArenaMate uses its built-in estimates. The settings popover identifies the active source and still supports user-supplied CSV ratings.

The contextual scorer tracks removal, board clears, draw, generation, recovery, reach, early board cards, late threats, and curve pressure. Adjustments depend on draft stage, and every recommendation reports whether the evidence is clear, favored, close, or limited. Completed pick decisions are retained only in the user's ArenaMate Application Support directory; the settings popover can copy this local history for comparison and tuning. ArenaMate does not upload draft history.

## Roadmap for Codex

1. Fix capture and OCR against actual Hearthstone screenshots, including legendary groups, avoiding false positions from sidebars and hover cards.
2. Establish stable bundle signing, permissions and diagnostic reporting without flooding users with permission prompts.
3. Preserve the compact interface while fixing automated detection.
4. Validate the Sparkle update flow on a Mac, then replace ad-hoc CI signing with Developer ID / notarization for public distribution.

See `CODEX_HANDOFF.md` for actionable acceptance criteria.
