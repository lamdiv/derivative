# Derivative Native prototype

An isolated macOS prototype: **SwiftUI controls + AppKit window/view composition + Chromium Embedded Framework (CEF)**. The Electron browser remains unchanged.

This is a feasibility and memory-comparison build, not the complete browser migration.

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

- One real, sandbox-enabled Chromium webpage, with navigation and text input.
- A SwiftUI sidebar with three starter favorites and current-page navigation.
- Fixed or floating sidebar via ⌘S; left-edge hover reveals the floating sidebar.
- Native fullscreen with the page filling the content area and the sidebar above it.
- Native ⌘T search, ⌘L address editing, Escape dismissal, and Return navigation.
- Native back/forward/reload controls and macOS window buttons.
- Orderly Chromium shutdown when the window closes or the app quits.

The prototype currently uses a dark lavender appearance. Multiple tabs, separate Space profiles, editable favorites, folders, split view, downloads, and the full settings/theme system still belong to the Electron implementation. Website popup windows and downloads are blocked in the prototype rather than partially implemented.

The native app stores its own website data under `~/Library/Application Support/Derivative Native Prototype`. It does not read or migrate Electron data. Use `DERIVATIVE_NATIVE_USER_DATA=/absolute/path` to select an isolated native profile.

## Verify

Install the root project's development dependencies (`npm ci`) for Playwright-based checks:

```sh
node native/scripts/verify.mjs
```

This launches a fresh native profile against a local HTTP fixture and checks rendering, text input, link navigation, back-navigation form restoration, absence of Node globals in website content, and clean shutdown. Set `KEEP_NATIVE=1` to leave the fixture running for UI inspection, then quit the app normally. Remote debugging is enabled only by the test launch flags.

Native sidebar/search/window behavior was also inspected through macOS accessibility and screenshots. The automated webpage fixture does not prove every native gesture or third-party sign-in flow.

## Compare memory

Build both apps first:

```sh
npm run build
python3 native/scripts/build.py
node native/scripts/compare-memory.mjs
```

The script launches each app with one copy of the same local page, a fixed 288px sidebar, and a fresh profile. After three seconds settling, it takes seven process-tree resident-set samples and writes `test-results/native-memory.json`.

One local run measured a median summed RSS of **654.5 MiB for the native prototype** and **841.0 MiB for Electron**. Native Chromium was 156.0.8078.17; Electron Chromium was 156.0.8078.48.

These are diagnostic process totals. Shared memory can be counted more than once, the native app has fewer features, and engine patch versions differ. This is not a unique physical-memory measurement, a multi-tab benchmark, or evidence that a complete native port would use 22% less RAM. The result supports further investigation rather than replacing the existing browser immediately.

## Implementation

- `Sources/BrowserUI.swift`: SwiftUI controls, AppKit window/layout, native menus and events.
- `Sources/Browser.mm`: CEF lifecycle/navigation callbacks and the narrow C bridge to Swift.
- `Sources/Helper.cc`: sandbox initialization and CEF subprocess entry point.
- `Sources/Bridge.h`: trusted native function declarations; no privileged JavaScript bridge is exposed to websites.
- `scripts/build.py`: pinned dependency setup, compilation, app-bundle layout, and local signing.

CEF's macOS application/event-loop and helper setup follows the official [embedding documentation](https://chromiumembedded.github.io/cef/general_usage.html) and [cefsimple examples](https://github.com/chromiumembedded/cef/tree/master/tests/cefsimple). The relevant license is retained in `ThirdParty/CEF-LICENSE.txt`; CEF/Chromium credits are also copied into the built app.
