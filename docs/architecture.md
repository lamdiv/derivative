# Architecture

Derivative uses SwiftUI controls, AppKit windows, and sandbox-enabled Chromium Embedded Framework (CEF) views. Website pages run separately from the trusted Swift interface, with no privileged JavaScript bridge.

## Source map

| Area | Responsibility |
| --- | --- |
| `native/Sources/BrowserState.swift` | Validated Codable metadata, restoration, and atomic storage |
| `native/Sources/Organization.swift` | Spaces, favorites, folders, tab placement, and swipe state |
| `native/Sources/BrowserUI.swift` | AppKit window composition, webpage attachment, and overlays |
| `native/Sources/BrowserFeatures.swift` | Actions, menus, shortcuts, downloads, and split coordination |
| `native/Sources/NativeControls.swift` | SwiftUI sidebar, search, drag targets, and new-tab view |
| `native/Sources/SettingsView.swift` | Settings, downloads, and supporting panels |
| `native/Sources/GlassSurface.swift` | Native glass and older-system accessibility fallbacks |
| `native/Sources/Browser.mm` | CEF lifecycle, contexts, navigation, permissions, and downloads |
| `native/Sources/Bridge.h` | Narrow C interface between Swift and Chromium |
| `native/Sources/Helper.cc` | Chromium subprocess entry point |
| `native/Tests/` | State, engine package, and media fixtures |
| `native/scripts/` | Build tools and isolated browser integration checks |
| `assets/` | App logo and committed PNG/ICNS icon assets |

The earlier Electron implementation is available in Git history. This branch contains the native app and its development tools.

## Window and webpage layout

AppKit owns the main window. Loaded background browser views detach while retaining live page state; restored background tabs load only when selected. Closing a tab releases its browser. Split view attaches two live browsers with explicit frames, and focusing either pane selects the browser used by navigation and shortcuts.

Search, settings, and the floating sidebar sit above the webpage host without resizing it. A normal window reserves space for the fixed sidebar and a small page inset. Maximized and fullscreen pages fill the viewport; revealing the sidebar overlays the page. Window controls align with the normal sidebar, while AppKit owns their fullscreen top-bar reveal.

SwiftUI provides native glass on macOS 26+, with frosted and Reduce Transparency fallbacks. Decorative highlights and outgoing Space-transition snapshots do not receive pointer events. Space gestures retain their initial axis, commit at most one switch, and ignore momentum for further switching.

## Spaces and persistence

Each Space has a persistent CEF request context for cookies and website storage. Switching Spaces preserves loaded pages. Moving a tab across Spaces waits for its old browser to close before opening it in the destination context; cancelling a before-unload dialog cancels the move.

Favorites belong to a Space, with up to twelve per collection. Moving a favorite transfers its saved link; an already-open page remains in its original profile as a regular tab. Version 2 metadata converts earlier shared favorites into independent collections and backs up the original metadata before conversion.

Metadata writes are debounced, serialized, and atomic. Tabs, folders, favorites, preferences, and shared history are stored in `native-state.json`. Website data lives in direct-child `Space-<ID>` directories. Open-tab search suggestions are scoped to the current Space. Metadata does not store website passwords or session tokens.

The existing data directory is retained for compatibility. For isolated development data:

```sh
DERIVATIVE_NATIVE_USER_DATA=/absolute/path/to/test-profile \
  native/build/Derivative.app/Contents/MacOS/Derivative
```

See [storage details](../native/README.md#data-and-profiles) for migration behavior. Split arrangements, recently closed tabs, and download history are session-only; unsaved forms and back/forward history survive ordinary tab switches but not app restarts.

## Trust boundaries

Website JavaScript has no Node runtime or privileged browser bridge. CEF handles websites in subprocesses; the native interface calls the narrow trusted C bridge. HTTP(S) popup links open tabs in the opener's profile. Mail and telephone links require native confirmation, unsupported schemes are blocked, and certificates are validated.

Supported website permissions require native confirmation; unsupported permissions are denied. Download paths come from native save dialogs. Only explicit completed-download actions open files. Browsing-data clearing also asks for confirmation. These controls do not replace a complete security audit.

## Build and verification

The engine archive and checksums are pinned in `native/cef.lock.json`. The build verifies the framework, assembles the helper bundles, and signs the app locally. Custom-engine selection also validates the framework's identity. Codec source builds are described in the [build guide](../native/README.md#video-compatibility-and-engine-builds).

Integration fixtures create temporary profiles, use local webpages, and launch background windows that ignore physical input. A private test-directory driver invokes native actions; real webpage state is checked over CDP. Test launches use a mock Keychain. None of this test interface is exposed to website JavaScript.

See the [testing guide](../native/README.md#verify) for commands and [verification notes](verification.md) for tested behavior and remaining limits.
