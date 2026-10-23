# Automatic updates

ArenaMate uses Sparkle 2.9.6, pinned in the Xcode project and its package resolution file. The portable core package remains independent of Sparkle. The app includes **ArenaMate → Check for Updates…** and **Automatically Check for Updates**. Sparkle manages the initial consent prompt, scheduled checks, download/install UI, and relaunch. Updates require user consent; silent unattended installation is not enabled.

The app trusts an Ed25519 public key embedded at build time. Both the feed and update archive must be signed. Builds without a valid public key keep the updater disabled; they do not accept unsigned updates or repeatedly display setup errors.

The feed URL is:

```
https://github.com/matthewalessandri/ArenaMate-releases/releases/latest/download/appcast.xml
```

The application source stays in the private `matthewalessandri/ArenaMate` repository. Only compiled app downloads and the signed feed are published to the separate public `matthewalessandri/ArenaMate-releases` repository. Sparkle does not use your GitHub login. Prereleases are not published to this stable update channel.

## One-time public download repository setup

Create **matthewalessandri/ArenaMate-releases** as a **public** repository with a README and default branch `main`. Do not copy the private source repository into it.

Create a fine-grained GitHub token scoped only to `ArenaMate-releases` with **Contents: Read and write** permission. Store it as the private source repository's Actions secret **ARENAMATE_RELEASES_TOKEN**. The source workflow's built-in `GITHUB_TOKEN` cannot publish to a different repository. Set an expiration you can maintain and renew the secret before expiry. Never include this publishing token in the app.

## One-time signing setup on a Mac

Use full Xcode. Resolve the pinned package from the checkout root:

```sh
xcodebuild -resolvePackageDependencies -project ArenaMate.xcodeproj \
  -scheme ArenaMate -clonedSourcePackagesDirPath "$PWD/.SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile
```

Sparkle's tools are in `.SourcePackages/artifacts/sparkle/Sparkle/bin/`. Run `generate_keys` once to create an update key in your login Keychain. Keep a secure backup of that key; reuse it for every release. Do not generate a replacement for each build. These keys are separate from Apple code-signing certificates.

Configure these repository settings under **Settings → Secrets and variables → Actions**:

- Repository **variable** `SPARKLE_PUBLIC_ED_KEY`: the public key printed by `generate_keys` (or `generate_keys -p`).
- Repository **secret** `SPARKLE_PRIVATE_ED_KEY`: the contents exported by `generate_keys -x <new-private-file>`.

Never put the private key in the checkout, app, logs, or chat. With an authenticated GitHub CLI, the following transfers it without printing its value (requires an existing Keychain key from the preceding step):

```sh
sparkle_tools="$PWD/.SourcePackages/artifacts/sparkle/Sparkle/bin"
gh variable set SPARKLE_PUBLIC_ED_KEY --repo matthewalessandri/ArenaMate \
  --body "$("$sparkle_tools/generate_keys" -p)"
(
  set -eu
  umask 077
  key_dir=$(mktemp -d)
  trap 'rm -rf "$key_dir"' EXIT
  "$sparkle_tools/generate_keys" -x "$key_dir/private-key"
  gh secret set SPARKLE_PRIVATE_ED_KEY --repo matthewalessandri/ArenaMate < "$key_dir/private-key"
)
```

Do not change the public key after distributing the first updater-enabled build without following Sparkle's documented key-rotation procedure.

## Release and install

1. Merge the updater changes and card-recognition fix. Verify the macOS workflow's core tests and universal Xcode build pass.
2. Publish a stable GitHub Release from the intended commit with a tag such as `v4.6.2`. Tags must be three numeric components, with an optional `v`. Do not reuse release tags. The workflow run number supplies an increasing `CFBundleVersion`; the tag supplies the displayed version. Keep the workflow's run counter intact when changing release automation.
3. The workflow checks signing and publishing requirements, builds arm64 and x86_64, verifies app code signatures and architectures, packages the app, and generates a signed feed and archive. It independently checks the archive signature against the public key using CryptoKit and verifies the feed signature before uploading anything. It creates a draft release in the public downloads repository, uploads every asset, then publishes it as the latest release. Missing or mismatched keys fail publication. Existing release tags and assets are never overwritten automatically; inspect and remove an incomplete draft before retrying. Private source-release notes are not copied into public downloads.
4. Wait for success and confirm `ArenaMate.dmg`, `ArenaMate-update.zip`, and `appcast.xml` are attached to the corresponding release in the **public downloads repository**. Publishing a release alone does not mean its build or upload succeeded. GitHub's latest stable release must point to this version for automatic checks to find it. A new release can briefly return a missing feed while CI is still running.
5. Install this updater-enabled app manually once. Older ArenaMate copies cannot discover an updater they do not contain. Keep the app in a writable stable location such as `~/Applications/ArenaMate.app`.
6. On the Mac, allow automatic checks when Sparkle asks, or use the menu toggle. Later stable releases can then be offered and installed from inside the app.

Local `Build-Mac-App.command` builds enable updates when the public key is provided as `SPARKLE_PUBLIC_ED_KEY` in that shell; the private key is never needed to build or run the app. Without the public key, the update menu is disabled. Local development builds have build number 1; use CI-produced release builds for realistic upgrade testing.

## Required macOS validation before claiming updates work

Install the first signed-feed build, then publish a second test release with a higher build number using the same update key. From the older app, check for updates, install, and verify relaunch and the new version. Verify saved draft picks persist, and verify Hearthstone capture after replacement. Test on Apple silicon and Intel if distributing to both.

The existing CI still uses ad-hoc Apple code signing. Ed25519 signatures authenticate updates, but do not replace Developer ID signing or Apple notarization. Gatekeeper warnings and renewed screen-recording permission requests remain possible. Configure stable Developer ID signing and notarization separately before broad distribution.

Linux checks cover the core tests, release-input validation, and appcast metadata rejection. They cannot build Sparkle's macOS framework or prove installation, relaunch, permissions, or live capture.
