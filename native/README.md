# Derivative for macOS

Derivative uses **SwiftUI for its interface, AppKit for window composition, and Chromium Embedded Framework (CEF) for websites**. The application, menu bar, window titles, and About section are all named Derivative.

## Build and run

Requires Apple Silicon, macOS 14+, Python 3.12+, and Apple command-line tools with Swift/C++ support. The build has been verified with Swift 6.4 and Apple clang 21; a full Xcode installation is not required.

From the repository root:

```sh
python3 native/scripts/build.py
open "native/build/Derivative.app"
```

The first build downloads an approximately 135 MB official CEF archive and installs pinned CMake/Ninja versions in an isolated Python environment. `cef.lock.json` pins the framework and checksums. Dependencies and generated bundles are ignored by Git.

The signed app is assembled in a repository-specific temporary directory and linked from `native/build/Derivative.app`. This avoids File Provider metadata interfering with signing in synced Desktop folders. Rebuild if temporary files are purged. Development signing is ad hoc; distribution requires Developer ID signing and notarization.

## Everyday browsing

- **Favorites:** up to twelve sites in balanced rows, with two tiles sharing a row equally. Add with the plus button, right-click to edit, copy, open, or remove, and drag to rearrange. An open favorite is highlighted in the grid.
- **Tabs and folders:** pin, duplicate, close, reopen, reorder, and move tabs. The menu beside the Space name creates folders. Drop tabs into a folder, Pinned, Today, or another Space. Right-click menus provide the same organization actions.
- **Spaces:** each Space has separate persistent cookies and website storage. Create, rename, recolor, delete empty Spaces, and drag to reorder their icons. Horizontal sidebar swipes animate the change and resist at either end.
- **Split view:** drop onto the middle of another tab to join two live pages. The top and bottom edges reorder instead. A joined sidebar row stays in the original tab section and uses website icons and titles. Click either page to focus it, drag the divider to resize, and right-click the joined row to separate or close panes.
- **Search:** ⌘T opens a floating search panel; ⌘L edits the address. Suggestions include tabs in the current Space, history, websites, search, and commands. Empty Spaces show history matches only after typing. Results have close controls. Typing in an empty Space opens the regular floating search panel and creates a tab only after confirmation.
- **Sidebar:** fixed, floating on hover, or hidden, with compact, comfortable, and wide widths. The sidebar overlays the full page when maximized/fullscreen. Restoring the window restores its normal sidebar mode.
- **Settings:** light/dark/system appearances, pastel Space colors, search engine, restoration, browsing-data clearing, Space management, downloads, shortcuts, and About Derivative.
- **Downloads:** a floating panel above the footer button with live progress, cancellation, and completed-file Open / Show in Finder actions, plus native save dialogs.
- **Keyboard:** Arc-style defaults, recent tabs across Spaces, reopen closed tabs, tab/Space cycling, numbered selection, hard reload, and URL copying. The complete reference is in Settings → Shortcuts.
- **Webpage menus:** right-click links and images to open in a new tab or split view, save, copy, search by image, or inspect. Selected text offers web search; editable fields retain Chromium’s editing and spelling commands. Separate browser/private windows and a mini-browser are not implemented.
- **Website handling:** HTTP(S) popups become tabs in their opener's profile; mail/telephone links require confirmation. Website permissions use native prompts. Failed pages show a native retry screen. Certificate validation remains enabled.

Loaded background pages retain live form state while their views are detached. Restored tabs load lazily. Moving a tab to another Space reloads it under the destination profile. Metadata is written atomically. Restart restores URLs and organization, not unsaved forms or webpage navigation history. Split arrangements, recently closed tabs, and download history are session-only.

Existing browser data remains at `~/Library/Application Support/Derivative Native Prototype` for compatibility with earlier builds. This is an internal storage path, not the app name. Use `DERIVATIVE_NATIVE_USER_DATA=/absolute/path` for an isolated profile. Website profiles are direct-child `Space-<ID>` directories; metadata is `native-state.json`.

## Verify

Install the repository development dependencies (`npm ci`) for Chromium integration checks:

```sh
node native/scripts/verify.mjs
node native/scripts/tabs-profiles.mjs
node native/scripts/sidebar-layout.mjs
node native/scripts/sidebar-animation.mjs
node native/scripts/features.mjs
node native/scripts/context-menu.mjs
```

Run GUI fixtures sequentially. They use isolated profiles, a local HTTP server, and Chromium's test-only mock Keychain option. Automated windows stay in the background and ignore physical input. A private test-directory driver invokes native actions; no privileged interface is exposed to websites. Real page state is checked over per-page CDP connections.

- `verify.mjs`: rendering, input, navigation, live form restoration, absence of Node globals, and shutdown.
- `tabs-profiles.mjs`: lazy restore, retained forms, hidden background pages, view destruction, per-Space storage isolation, popup ownership, restart, and multi-tab quit.
- `sidebar-animation.mjs`: real intermediate slide positions, rapid hover reversal, stable webpage bounds, and promotion from the empty page to regular search.
- `sidebar-layout.mjs`: actual AppKit/SwiftUI header frames, traffic-light alignment after title-bar relayout, three widths, short windows, twelve favorites, floating reveal, and fullscreen composition without changing the desktop Space.
- `context-menu.mjs`: real Chromium context targets, link and split actions, image downloads, editing/selection menus, and developer tools.
- `features.mjs`: favorites/folders, split attachment and sizing, settings/themes, recent/reopened tabs, downloaded bytes and cancellation, profile-safe moves, scoped search, swipe edges, Space management, cookie/history/cache clearing, and quit.

Pure Swift checks:

```sh
xcrun swiftc -swift-version 5 -module-cache-path native/.cache/swift-modules \
  native/Sources/BrowserState.swift native/Sources/Organization.swift native/Sources/FavoriteLayout.swift \
  native/Tests/StateTests.swift -o native/build/state-tests
native/build/state-tests
```

The interface has also been inspected using macOS accessibility and screenshots. Automated controller checks do not establish every physical trackpad gesture, website sign-in, permission grant, save dialog, media/DRM flow, or fullscreen animation.

## Performance

```sh
npm run build
python3 native/scripts/build.py
node native/scripts/compare-memory.mjs
```

The comparison uses one local page, fresh profiles, seven settled process-tree RSS samples, and the same sidebar width. Results are saved to ignored `test-results/native-memory.json`. Earlier builds measured 693.4 MiB native versus 854.8 MiB Electron, before the full feature port. That historical result is not a measurement of the current build or a guaranteed saving: shared memory may be counted twice, feature sets and engine patches differed, and RSS is not unique physical footprint.

## Source map

| File | Responsibility |
| --- | --- |
| `Sources/BrowserUI.swift` | Window composition, native events, lifecycle, and callbacks |
| `Sources/BrowserFeatures.swift` | Settings, menus, shortcuts, swipes, tab moves, and split coordination |
| `Sources/NativeControls.swift` | Sidebar, drag targets, favorites, search, and new-tab interface |
| `Sources/SettingsView.swift` | Settings, downloads, recent tabs, and page-error views |
| `Sources/BrowserState.swift` | Validated metadata and atomic storage |
| `Sources/Organization.swift` | Favorite/folder/tab/Space operations and gesture state |
| `Sources/Browser.mm` | CEF profiles, webpage views, split layout, downloads, permissions, and navigation |
| `Sources/Helper.cc` | Sandboxed Chromium subprocess entry point |
| `Sources/Bridge.h` | Narrow trusted C interface between Swift and Chromium |

CEF setup follows its official embedding examples. Licenses and Chromium credits are retained under `ThirdParty/` and in the app bundle.
