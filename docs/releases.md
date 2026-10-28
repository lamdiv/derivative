# Distributing Derivative for macOS

Derivative currently targets Apple Silicon and macOS 14+. Public builds should be Developer ID signed and notarized. The existing v0.1.0-preview.1 download is an older, unnotarized preview; adding a developer account does not change that download.

## One-time setup on the signing Mac

1. In **Xcode → Settings → Accounts**, add the Apple account with the active Developer Program membership. Select the team and **Manage Certificates → + → Developer ID Application**. This must include a private key on this Mac; a downloaded `.cer` alone is not sufficient.
2. Verify the identity:

   ```sh
   security find-identity -v -p codesigning
   ```

3. Store notarization credentials interactively in Keychain:

   ```sh
   DEVELOPER_DIR=/Library/Developer/CommandLineTools xcrun notarytool store-credentials derivative-notary
   ```

   Supply the Apple account, Developer Team ID, and an app-specific password when prompted. Do not put passwords, private keys, `.p12` files, or API keys in the repository or chat. An App Store Connect API key is another supported authentication option; see Apple's documentation below.

## Build, sign, and notarize

Install development dependencies with `npm ci` for the signed browser smoke test. Substitute the exact **Developer ID Application** identity from Keychain:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools python3 native/scripts/package.py \
  --version 0.1.0-preview.2 \
  --identity 'Developer ID Application: Your Name (TEAMID)' \
  --notary-profile derivative-notary
```

The command builds a fresh app, stages an independent copy, and signs from the inside out: bundled native libraries, CEF framework, helper apps, then the outer app. Executable processes use the hardened runtime and secure timestamps. Only renderer/GPU helpers get JIT permission. Release signatures exclude debugging and blanket library-validation exceptions. The script rejects native code outside the known signing inventory.

It runs the browser smoke test and a real-Keychain encrypted-cookie restart test against the hardened app (using an isolated profile and a test-only item that is removed afterward), submits an app archive, requires Apple's **Accepted** status, staples the app, and checks Gatekeeper. Then it creates the ZIP from the stapled app, creates/signs the DMG, submits and staples the DMG, and assesses that container. `build-info.json` records the Team ID and both notarization submission IDs. Final checksums are generated after stapling.

Apple can take time to process a first submission. If the wait times out, do not delete staging or submit another copy. Run the same command with `--resume`. It requires the same source commit, version, identity, and Keychain profile and checks the existing submission. Receipts and rejection logs remain in ignored `release/<version>/.notary/`. The temporary signing stage stays outside the Desktop checkout to avoid File Provider metadata; `.work/stage-path.txt` records its location for resume. Keep both until distribution completes. Inspect a rejection before rebuilding under a new version.

The output is a DMG, ZIP, build manifest, and `SHA256SUMS` in `release/<version>/`. Do not distribute incomplete output: the command must succeed and the manifest must report `notarized: true`.

## Validate before publishing

Mount the DMG read-only, copy its app to a fresh location, and verify that installed copy. Also extract and verify the ZIP:

```sh
codesign --verify --deep --strict /path/to/Derivative.app
xcrun stapler validate /path/to/Derivative.app
spctl --assess --type execute --verbose=2 /path/to/Derivative.app
DERIVATIVE_NATIVE_APP=/path/to/Derivative.app npm run test:browser
shasum -a 256 -c SHA256SUMS
```

Check the downloaded installer through Finder on a clean Gatekeeper-enabled Mac. Test launch, web rendering, JavaScript, GPU rendering, downloads, permission prompts, quit and relaunch. Signing is not a claim of complete application security or media compatibility. Keep the documented codec and browser-service limitations in the release notes.

Publish only the four final files as GitHub release assets. Exclude hidden staging and notarization directories. Tag the exact `sourceCommit` recorded in `build-info.json`; never commit app bundles or engine binaries. Verify public download hashes, then update README links and the release's signing status. Older downloads remain unnotarized.

## Existing unsigned CI previews

Without `--identity` and `--notary-profile`, the packager still produces an explicitly unnotarized, ad-hoc preview. The `Unsigned macOS preview (manual)` workflow uses this mode: **it is not a signed release pipeline**. It requires an explicit manual run against an existing tag; pushing a new signed release tag must not publish a competing unsigned build. Local certificates and profiles are not available on GitHub runners. A future CI signing setup needs a separately configured protected signing environment and credentials; do not commit them or silently fall back to unsigned distribution. The workflow on older commits can still have its former automatic trigger; tag signed releases only at a commit with the updated manual workflow.

## References

- [Apple: Create Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
- [Apple: Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [CEF: Code signing](https://github.com/chromiumembedded/cef/blob/master/docs/code_signing.md)
- Entitlement references: Chromium `156.0.8078.17`, `chrome/app/app-entitlements.plist` and `helper-renderer-entitlements.plist`. Derivative limits main-app capabilities to its existing camera, microphone, Bluetooth, printing, and location features.

## Installer presentation

`installer.py` creates a 640 × 420 Finder window with Retina pastel artwork, the app on the left, a visible arrow, and an Applications shortcut on the right. Only those two items are visible. `dmgbuild` writes the saved icon view and background metadata without Finder automation. The app bundle is not given Finder metadata flags, which would invalidate strict signature verification.

For a presentation-only release, reuse the previous signed app without rebuilding or resubmitting it:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools python3 native/scripts/repackage.py \
  --from-version 0.1.0-preview.2 --version 0.1.0-preview.3 \
  --identity 'Developer ID Application: Your Name (TEAMID)' \
  --notary-profile derivative-notary
```

This verifies the source checksums and app signature/ticket, preserves the ZIP byte for byte, and submits only the newly signed DMG to Apple. `--resume` reuses its submission after a timeout. The manifest keeps `sourceCommit` for the original app and adds `installerSourceCommit` for the new packaging; tag that packaging commit for this release. The app inside and its bundle version remain unchanged.
