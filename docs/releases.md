# Packaging a macOS preview

On an Apple Silicon Mac with the build prerequisites installed:

```sh
DEVELOPER_DIR=/Library/Developer/CommandLineTools npm run package -- --version 0.1.0-preview.1
```

The command builds the app, validates its signature and bundle environment, and creates a DMG, ZIP, build manifest, and `SHA256SUMS` in the ignored `release/<version>/` directory. `--skip-build` packages an existing verified build. The base version must match the app bundle version. Existing installers are never overwritten.

Before publishing, mount the DMG read-only, copy the app to a new location, and verify that copy:

```sh
codesign --verify --deep --strict /path/to/Derivative.app
DERIVATIVE_NATIVE_APP=/path/to/Derivative.app npm run test:browser
shasum -a 256 -c SHA256SUMS
```

Publish all four files as assets on a GitHub **prerelease**, tagged at the `sourceCommit` in `build-info.json`. Never commit app bundles or engine binaries to Git. Verify the public downloads after publishing.

The `macOS preview release` workflow runs on an Apple Silicon macOS 26 runner when a `v*-preview.*` tag is pushed. It builds a fresh app, checks both installers, runs the browser smoke test on a relocated copy, and uploads assets to a draft before publishing it as a prerelease. Push tags only at reviewed commits; a failed upload leaves a draft for inspection.

These packages are ad-hoc signed, not Developer ID signed or notarized. State that prominently in release notes, together with Apple Silicon/macOS 14 requirements, installation steps, and current media and browser-service limitations. Do not describe previews as production-ready or recommend disabling Gatekeeper.
