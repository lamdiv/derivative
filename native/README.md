# Derivative Native prototype

An incremental native macOS migration: **SwiftUI controls + AppKit window/view composition + Chromium Embedded Framework (CEF)**. The Electron browser remains unchanged.

The native browser now has working tabs, Spaces, and persistent profiles. Feature parity is still in progress; keep the Electron version available while evaluating it.

## Build and run

Requires Apple Silicon, macOS 14+, Python 3.12+, and a current Apple command-line toolchain with Swift/C++ support. This workspace was verified with Swift 6.4 and Apple clang 21. A full Xcode installation is not required by this build script.

From the repository root:

```sh
python3 native/scripts/build.py
open "native/build/Derivative Native.app"
```

The first build downloads an approximately 135 MB official CEF archive and installs pinned CMake/Ninja versions in an isolated Python environment. The CEF version and checksums are recorded in `cef.lock.json`; framework binaries, tools, and build outputs are ignored by Git. There is no Chromium source checkout.

The signed app is assembled in a repository-specific temporary directory and linked from `native/build/Derivative Native.app`. This avoids Finder/File Provider metadata interfering with signing inside synced Desktop folders. If temporary files are purged, rerun the build. Signing is ad hoc for local development, without a distribution identity or notarization.

## What works

- Real, sandbox-enabled Chromium tabs with navigation, input, close/pin/duplicate controls, and lazy restoration. Inactive views detach while remaining alive, and Chromium reports their pages as hidden.
- A SwiftUI sidebar with the three-column favorites grid, active favorite ownership, tab rows, and compact Space icons.
- Separate persistent website profiles for Personal, Work, and Study; loaded tabs preserve page state when switching.
- Fixed or floating sidebar via ⌘S; left-edge hover reveals the floating sidebar.
- Native fullscreen with the page filling the content area and the sidebar above it.
- Native ⌘T search, ⌘L address editing, Escape dismissal, and Return navigation. Tabs are created only after confirmation; empty Spaces reuse their existing search.
- Search suggestions and result-close actions scoped to the current Space.
- Website popup links open tabs in their opener’s Space/profile.
- Native back/forward/reload controls and macOS window buttons.
- Orderly Chromium shutdown when the window closes or the app quits.

The current native appearance uses dark pastel colors per Space. Editable favorites, folders, drag organization, swipe gestures, split view, downloads, and the full settings/light-theme system still belong to the Electron implementation. Downloads are blocked until migrated.

The native app stores its own website data under `~/Library/Application Support/Derivative Native Prototype`. Metadata is saved atomically as `native-state.json`; CEF profiles use direct child directories named `Space-<ID>`. It does not read or migrate Electron data. Use `DERIVATIVE_NATIVE_USER_DATA=/absolute/path` to select an isolated native profile.

## Verify

Install the root project's development dependencies (`npm ci`) for Playwright-based checks:

```sh
node native/scripts/verify.mjs
node native/scripts/tabs-profiles.mjs
node native/scripts/sidebar-layout.mjs
```

This launches a fresh native profile against a local HTTP fixture and checks rendering, text input, link navigation, back-navigation form restoration, absence of Node globals in website content, and clean shutdown. Set `KEEP_NATIVE=1` to leave the fixture running for UI inspection, then quit the app normally. Remote debugging is enabled only by the test launch flags.

Pure Swift state checks can also run without launching the GUI:

```sh
xcrun swiftc -swift-version 5 -module-cache-path native/.cache/swift-modules \
  native/Sources/BrowserState.swift native/Tests/StateTests.swift \
  -o native/build/state-tests
native/build/state-tests
```

The tabs/profile fixture checks live form retention, lazy restoration, per-Space cookie/storage isolation, view destruction, empty-Space search reuse, popup profile ownership, restart persistence, and multi-tab quit. It uses direct page-target CDP connections because CEF profiles have distinct debugger targets.

The sidebar fixture measures actual AppKit/SwiftUI header frames and traffic-light alignment across all three widths and window sizes, including the minimum window with 12 favorites. It checks floating reveals and fullscreen composition without entering a separate macOS Space; native fullscreen animations and hover gestures still need a visual check.

Automated windows refuse physical input and stay in the background. Isolated fixtures pass Chromium’s standard `--use-mock-keychain` test flag so they do not access the user’s Keychain; normal app launches do not use that flag. The native controller’s local test driver is enabled only by `DERIVATIVE_NATIVE_TEST_DIRECTORY`; it watches a private disposable directory and is absent from normal launches. It invokes native actions without exposing them to websites.

Native sidebar/search/window behavior was also inspected through macOS accessibility and screenshots. The automated webpage fixture does not prove every native gesture or third-party sign-in flow.

## Compare memory

Build both apps first:

```sh
npm run build
python3 native/scripts/build.py
node native/scripts/compare-memory.mjs
```

The script launches each app with one copy of the same local page, a fixed 288px sidebar, and a fresh profile. After three seconds settling, it takes seven process-tree resident-set samples and writes `test-results/native-memory.json`.

The initial single-page prototype (`7f50bb4`) measured a median summed RSS of **654.5 MiB for the native prototype** and **841.0 MiB for Electron**. Native Chromium was 156.0.8078.17; Electron Chromium was 156.0.8078.48.

After adding native tabs, persistent Space profiles, and the nine-favorite grid (`5249fea`), the same one-page fixture measured **693.4 MiB native versus 854.8 MiB Electron** (about 19% lower summed RSS). Both test profiles were fresh and automated windows refused physical input.

These are diagnostic process totals. Shared memory can be counted more than once, the native app has fewer features, and engine patch versions differ. This is not a unique physical-memory measurement, a multi-tab benchmark, or evidence that a complete native port would use 19–22% less RAM. The result supports further investigation rather than replacing the existing browser immediately.

## Implementation

- `Sources/BrowserUI.swift`: AppKit window/layout, native menus, events, and tab coordination.
- `Sources/NativeControls.swift`: SwiftUI sidebar, favorites, Space controls, search, and empty page.
- `Sources/BrowserState.swift`: validated metadata, tab/Space actions, and atomic persistence.
- `Sources/Browser.mm`: CEF lifecycle/navigation callbacks and the narrow C bridge to Swift.
- `Sources/Helper.cc`: sandbox initialization and CEF subprocess entry point.
- `Sources/Bridge.h`: trusted native function declarations; no privileged JavaScript bridge is exposed to websites.
- `scripts/build.py`: pinned dependency setup, compilation, app-bundle layout, and local signing.

CEF's macOS application/event-loop and helper setup follows the official [embedding documentation](https://chromiumembedded.github.io/cef/general_usage.html) and [cefsimple examples](https://github.com/chromiumembedded/cef/tree/master/tests/cefsimple). The relevant license is retained in `ThirdParty/CEF-LICENSE.txt`; CEF/Chromium credits are also copied into the built app.
