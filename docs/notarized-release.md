A signed and notarized macOS preview of Derivative, with Spaces, per-Space favorites, command search, a floating or fixed sidebar, split view, and pastel themes.

**Apple Silicon · macOS 14 or later.**

### Redesigned installer

The DMG opens with a pastel drag-to-install layout: Derivative on the left, a clear arrow, and Applications on the right. No Read Me file or extra visible files. The browser app and ZIP are unchanged from v0.1.0-preview.2; only the installer was repackaged, signed, and notarized again.

### Install

1. Download the `.dmg` below and open it.
2. Drag **Derivative** into **Applications**.
3. Open Derivative from Applications, then eject the installer.

This release is signed with Developer ID and notarized by Apple. Notarization tickets are attached to both the app and DMG. A normal “downloaded from the internet” confirmation may still appear. The older v0.1.0-preview.1 download remains unnotarized; use this release instead.

The ZIP alternative contains the same signed, notarized app. `SHA256SUMS` verifies the files; `build-info.json` records the source revision, engine identity, Team ID, and Apple submission IDs.

### Still an early preview

- WebM is supported. H.264/AAC, MP4 streaming, and DRM are not enabled, so some videos and YouTube livestreams will not play.
- Extensions, password management, sync, private browsing, and automatic updates are not implemented yet. Download new versions from Releases.
- Tabs and organization restore across launches. Unsaved forms, split arrangements, and download history are session-only.
- Notarization checks the submitted software for known malicious components; it is not a completed security audit or a guarantee that every browser feature works correctly.

[Website](https://derivativebrowser.com) · [Report an issue](https://github.com/lamdiv/derivative/issues)
