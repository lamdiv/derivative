This preview fixes repeated first-run requests for **Chromium Safe Storage**.

### Keychain startup fix

- New profiles use their own **Derivative Safe Storage** item instead of sharing Chromium's generic item.
- Existing profiles copy their original encryption key into the new app-owned item before Chromium starts, preserving encrypted cookies. An upgrade may require one approval to access the old item; subsequent launches reuse the saved identity.
- Development builds use a separate profile and Keychain service, so rebuilding the app cannot change the installed browser's Keychain permissions.
- Denied migration access stops startup with an explanation. It does not reset cookies, replace the old key, delete the shared Chromium item, or disable encryption.

### Install

**Apple Silicon · macOS 14 or later.** Download the DMG, drag Derivative to Applications, and replace the existing app. Keep your profile for the key-preserving upgrade. The app and installer are Developer ID signed and notarized; notarization tickets are attached. A normal downloaded-app confirmation may still appear.

The DMG includes the pastel drag-to-install layout. A ZIP alternative, checksums, and build manifest are included below. There is no automatic updater yet.

### Current limitations

H.264/AAC, MP4 streaming, and DRM are not enabled. Extensions, password management, sync, private browsing, and automatic updates are not implemented. This remains an early development preview.
