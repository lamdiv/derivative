# Architecture

Derivative's macOS app uses SwiftUI controls, AppKit windows, and sandboxed Chromium Embedded Framework views. Website pages run separately from the trusted Swift interface, with no privileged JavaScript bridge.

## macOS implementation

`native/Sources/BrowserState.swift` owns Codable metadata; `Organization.swift` implements favorite/folder/tab/Space operations. `BrowserUI.swift` composes the window, and `BrowserFeatures.swift` coordinates menus, keyboard/trackpad events, settings, downloads, and split panes. SwiftUI controls live in `NativeControls.swift` and `SettingsView.swift`.

`Browser.mm` owns CEF browsers and request contexts. Each Space gets a separate persistent context. Inactive views detach while retaining live page state. Split view attaches two browsers and gives them explicit frames; selecting either pane changes the active browser for navigation and shortcuts. Search and settings are native sibling views above the webpage host and do not resize it. Moving a tab across Spaces waits for its old browser to close before opening it in the destination context; a cancelled before-unload dialog cancels the move.

Metadata writes are debounced, serialized, and atomic. Website profiles are separate from Electron profiles. The existing native data path is retained for compatibility; see the [native guide](../native/README.md).

Permission requests and mail/telephone links require native confirmation. Unsupported schemes are blocked. Certificates are validated. Download paths come from the native save flow; only explicit completed-download actions open files. Test launch flags enable a private local action driver and mock Keychain; neither is exposed to website JavaScript.

## Electron implementation

The Electron app uses React for the interface and `WebContentsView` for native Chromium pages. Its implementation details follow.

## Project layout

| Path | Responsibility |
| --- | --- |
| `electron/main.ts` | Window lifecycle, macOS menu, native controls, trusted IPC |
| `electron/tabs/manager.ts` | Tab lifecycle, navigation, profiles, split views, permissions, downloads |
| `electron/windows/chrome-layer.ts` | Floating sidebar and popup view composition |
| `electron/windows/state-publisher.ts` | Per-renderer state snapshots and incremental updates |
| `electron/preload.ts` | Isolated bridge for the trusted local UI |
| `electron/storage/store.ts` | Validated restoration and serialized atomic metadata writes |
| `shared/` | State/action types, navigation, shortcuts, suggestions, organization |
| `src/` | React components, gesture handling, and styles |
| `assets/brand.json` | Shared vector geometry for the app mark and generated icons |
| `tests/` | Unit tests and local native integration fixtures |

## Native view composition

The root interface lives in a `BrowserWindow`. Loaded background website views remain alive but detached; restored background tabs load only when selected. Closing a tab closes its web contents. Split view attaches two website views at once, preserving both pages' input state.

A separate, preloaded transparent view renders trusted floating controls above websites. Modal panels cover the window; the floating sidebar covers only its own input region. Websites stay attached behind these controls. Exit transitions finish before the floating layer detaches, and reopening cancels stale detach timers.

Normal windows use an 8px webpage inset. Fixed sidebar widths are Compact (252px), Comfortable (288px), and Wide (320px), plus 16px of frame spacing. Maximized and fullscreen pages fill the viewport with zero padding and square native corners. Revealing or pinning the expanded sidebar does not resize the website. The expanded sidebar reaches the top of the content area and retains 8px side/bottom spacing and 14px corners.

In normal windows, native traffic lights align with the sidebar navigation row. In native fullscreen, macOS controls the top-edge reveal of the window controls. CSS does not claim to override macOS menu-bar or notch regions. Likewise, sidebar backdrop filtering operates within the trusted renderer rather than sampling a separate native website surface.

## Trust boundaries

Website views have Node integration disabled, context isolation, sandboxing, and web security enabled, with no privileged preload. The isolated browser bridge is exposed only to the local UI. IPC checks the exact UI URL and sender's main-frame identity, then validates action payloads.

Trusted UI navigation and popups are blocked. HTTP(S) website popups open as tabs. Mail and telephone links require native confirmation; other external schemes are blocked. Certificates are not bypassed. Supported website permissions ask through a native dialog, and unsupported permissions are denied. These boundaries do not replace a complete security audit.

## Profiles and storage

Browser metadata is stored in `app.getPath('userData')/browser-state.json`. Writes are debounced, serialized, and atomic. Invalid metadata falls back to a clean state; there is no recovery interface yet.

Each Space has a separate persistent Electron session for cookies, local storage, IndexedDB, and cache:

- Personal uses `persist:personal`.
- Other Spaces use `persist:space-<Space ID>`.

Switching Spaces preserves loaded pages. Moving a tab between Spaces reloads it in the destination profile. Closing tabs or quitting does not clear stored website data. History is currently shared across Spaces; open-tab search suggestions are scoped to the current Space.

Metadata stores browsing URLs and history, but excludes website passwords and session tokens. Website session data remains in Electron's profile storage. User-initiated data clearing asks for confirmation.

To use an isolated development profile:

```sh
DERIVATIVE_USER_DATA=/absolute/path/to/test-profile npm run dev
```

Native integration fixtures create and remove their own temporary profiles.

## Interaction performance

UI state crosses IPC as changed sections. Each trusted renderer keeps its own snapshot; the detached floating UI catches up when shown. Unchanged history is omitted from tab-switch updates, and private hover ownership does not broadcast UI state. Native attachment and border-radius calls are skipped when unchanged.

After building, run the local stress fixture:

```sh
PERF_ASSERT=1 node tests/performance.mjs
```

It uses 500 restored tabs, two loaded pages, and 2,000 history entries to report action round-trip medians/p95, transmitted state counts, and idle broadcasts. Timing includes test automation and does not measure frame rate or website loading speed. Development logging also records window readiness and main-process tab switching.

The [verification notes](verification.md) record measured results, test coverage, and unresolved native-suite timing failures. Neither these checks nor stored-cookie tests establish compatibility with every real sign-in provider or physical trackpad.
