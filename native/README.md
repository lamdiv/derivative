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

## Video compatibility and engine builds

The default official CEF archive supports WebM/VP9/Opus but does **not** support H.264/AAC in our playback fixture. This affects MP4 video, AAC audio, and MP4 Media Source Extensions. WebM on the project website is a fallback, not a browser-wide fix. DRM services require separate integration and are not enabled by the codec build below.

The source build workflow is prepared but has not yet been run end to end: this development Mac needs full Xcode. It builds the same pinned CEF/Chromium revisions with `proprietary_codecs=true ffmpeg_branding=Chrome`; no runtime switch or replacement website player is used. Source builds require full Xcode with first-launch setup completed, an Apple Silicon Mac, at least 200 GiB free initially, and substantial download/build time. Select the installed Xcode Developer directory before running it. The ordinary prebuilt-engine app build still only needs command-line tools.

```sh
python3 native/scripts/build-codecs.py --check
python3 native/scripts/build-codecs.py --plan
python3 native/scripts/build-codecs.py
```

The upstream automation script is pinned by commit and SHA-256. Sources stay in `native/.cache/codec-source`; use `--work-dir /absolute/path/without/spaces` for another build volume. Source revisions, GN flags, and the depot_tools revision are recorded with the resulting engine. The script compiles an isolated candidate app, requires real WebM and H.264/AAC decoding and seeking, verifies AAC samples and MP4 MSE playback, and runs the browser rendering/navigation smoke test. Only a successful candidate is selected for subsequent app builds. If Xcode is absent or a test fails, engine selection stays unchanged. The full Chromium build and candidate acceptance remain unverified until that source build completes.

Selection is recorded in ignored `native/.cache/selected-cef.json`, including the framework SHA-256. Normal app builds verify that selection and refuse an altered or outdated engine. The framework copy and C++ wrapper cache are keyed by framework bytes, so equal version numbers cannot accidentally retain the old codec-free framework. For a one-off candidate, use `python3 native/scripts/build.py --cef-dir /path/to/cef_binary_distribution --build-dir native/build/codec-candidate`. Build identity is retained inside the app at `Contents/Resources/ThirdParty/CEF-BUILD.json`. Remove the local selection file to return future builds to the official archive.

Before distributing a custom engine, resolve the licensing requirements for the enabled codecs. See [Google's CEF build guidance](https://support.google.com/webdesigner/answer/10043691?hl=en) and [CEF's platform-decoding discussion](https://github.com/chromiumembedded/cef/issues/3559). The experimental OS-only route discussed there does not establish working AAC support and is not used here. No codec licensing or DRM rights are supplied by this repository.

## Everyday browsing

- **Favorites:** fresh profiles start with the Derivative GitHub repository, derivativebrowser.com, and YouTube. Each Space has its own collection of up to twelve sites in balanced rows. Tiles have theme-aware hover and active states. Add with the plus button, right-click to edit, copy, move to another Space, or remove, and drag to rearrange. Drop a tile onto a Space icon to move it there. Moving a favorite keeps any live webpage in its original sign-in profile as a regular tab.
- **Tabs and folders:** pin, duplicate, close, reopen, reorder, and move tabs. The menu beside the Space name creates folders. Drop tabs into a folder, Pinned, Today, or another Space. Right-click menus provide the same organization actions.
- **Spaces:** each Space has separate persistent cookies and website storage. Create, rename, recolor, delete empty Spaces, and drag to reorder their icons. Favorites, the Space name, and tabs follow horizontal swipes with paired outgoing/incoming slides; navigation and footer controls stay stationary. Trackpad gestures retain their initial axis, switch at most one Space, and ignore momentum for switching. Edge hints overlay the sidebar without shifting its layout, and Reduce Motion skips large slides.
- **Split view:** drop onto the middle of another tab to join two live pages. The top and bottom edges reorder instead. A joined sidebar row stays in the original tab section and uses website icons and titles. Click either page to focus it, drag the divider to resize, and right-click the joined row to separate or close panes.
- **Address bar:** a compact domain label, copy-link feedback, and a site-controls popover with 25–300% page zoom, zoom reset, and per-tab muting. Use ⌘+ (or ⌘=), ⌘−, and ⌘0 to zoom in, out, or reset to 100%; the View menu offers the same controls. Click the domain to edit the complete URL.
- **Search:** ⌘T opens a floating search panel; ⌘L edits the address. The panel uses a readable glass-backed surface, theme-tinted selection, favicon tiles, and keyboard hints. Suggestions include tabs in the current Space, history, websites, search, and commands. Empty Spaces show history matches only after typing. Results have close controls. Typing in an empty Space opens the regular floating search panel and creates a tab only after confirmation.
- **Sidebar:** fixed, floating on hover, or hidden, with compact, comfortable, and wide presets. Drag its right edge for a remembered custom width, from 220 points to two-thirds of the window. A small inward drag stops at the minimum; release a deliberate drag below 132 points to collapse it. Toggling it back restores the 288-point default. Hover reveal overlays the full page when maximized/fullscreen; explicitly pinning the sidebar reserves its width and gives the webpage an 8-point inset and rounded corners. Restoring the window restores its normal sidebar mode.
- **Surfaces:** system Liquid Glass on macOS 26+ for the sidebar, search, settings, and popovers, with distinct pastel sidebar tones, gentler gradients, and quieter canvas colors in each light/dark palette. macOS 14–15 retain a frosted visual-effect fallback; Reduce Transparency uses opaque surfaces. Sidebar tiles and tab rows use system glass surfaces with subtle hover and selected tinting.
- **Settings:** separate Appearance, General, Spaces, Downloads, and Shortcuts sections. Visual Light/Dark/System cards and Lilac, Mint, Peach, Sky, and Rose swatches coordinate the glass tint and empty-page canvas. Spaces have inline color swatches; General groups search, restoration, and confirmed browsing-data clearing. Downloads include an empty state and shortcuts use readable keycaps.
- **Downloads:** a floating panel above the footer button with live progress, cancellation, and completed-file Open / Show in Finder actions, plus native save dialogs.
- **Keyboard:** Arc-style defaults, recent tabs across Spaces, reopen closed tabs, tab/Space cycling, numbered selection, hard reload, and URL copying. The complete reference is in Settings → Shortcuts.
- **Webpage menus:** right-click links and images to open in a new tab or split view, save, copy, search by image, or inspect. Selected text offers web search; editable fields retain Chromium’s editing and spelling commands. Separate browser/private windows and a mini-browser are not implemented.
- **Website handling:** HTTP(S) popups become tabs in their opener's profile; mail/telephone links require confirmation. Website permissions use native prompts. Failed pages show a native retry screen. Certificate validation remains enabled.

Loaded background pages retain live form state while their views are detached. Restored tabs load lazily. Moving a tab to another Space reloads it under the destination profile. Metadata is written atomically. Restart restores URLs and organization, not unsaved forms or webpage navigation history. Split arrangements, recently closed tabs, and download history are session-only.

## Data and profiles

Existing browser data remains at `~/Library/Application Support/Derivative Native Prototype` for compatibility with earlier builds. This is an internal storage path, not the app name. Use `DERIVATIVE_NATIVE_USER_DATA=/absolute/path` for an isolated profile. Website profiles are direct-child `Space-<ID>` directories; metadata is `native-state.json`.

Metadata version 2 assigns favorites to Spaces. Existing shared favorites are copied once into independent collections for each existing Space, preserving their order and rebinding open favorite tabs to the correct copy. The original metadata is backed up as `native-state-before-space-favorites.json` before conversion. The original nine-site starter collection is replaced by the three current defaults only when every original name and URL remains unchanged; customized collections are preserved, with a `native-state-before-default-favorites.json` backup before replacement. New Spaces start with an empty collection. Removing a Space without open tabs also removes that Space's favorite collection. Do not open version 2 metadata with an older build that only understands version 1.

## Verify

Install the repository development dependencies (`npm ci`) for Chromium integration checks:

```sh
node native/scripts/verify.mjs
node native/scripts/tabs-profiles.mjs
node native/scripts/sidebar-layout.mjs
node native/scripts/sidebar-animation.mjs
node native/scripts/features.mjs
node native/scripts/context-menu.mjs
node native/scripts/media.mjs
# Acceptance gate for an engine intended to provide H.264/AAC:
node native/scripts/media.mjs --require-proprietary
```

Run GUI fixtures sequentially. They use isolated profiles, a local HTTP server, and Chromium's test-only mock Keychain option. Automated windows stay in the background and ignore physical input. A private test-directory driver invokes native actions; no privileged interface is exposed to websites. Real page state is checked over per-page CDP connections.

- `verify.mjs`: rendering, input, navigation, live form restoration, absence of Node globals, and shutdown.
- `media.mjs`: decoded video frames and seeking, AAC decoded samples, and fragmented MP4 MSE playback; reports capabilities to `test-results/native-media.json`. The default mode records missing proprietary codecs; `--require-proprietary` fails unless all checks pass. `--app /path/to/Derivative.app` selects an isolated candidate.
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

Engine package identity guards: `python3 native/Tests/EngineBuildTests.py`.

The interface has also been inspected using macOS accessibility and screenshots. Automated controller checks do not establish every physical trackpad gesture, website sign-in, permission grant, save dialog, media/DRM flow, or fullscreen animation.

## Performance

Restored background tabs load only when selected. Loaded background pages retain their live state while their views are detached. CEF still uses Chromium browser, renderer, and helper processes; memory use depends on the pages you open.

Historical comparisons with the earlier app are recorded in [verification notes](../docs/verification.md). They predate the current feature set and are not a current memory-saving claim. The retired comparison fixture is available in Git history.

## Source map

| File | Responsibility |
| --- | --- |
| `Sources/BrowserUI.swift` | Window composition, native events, lifecycle, and callbacks |
| `Sources/BrowserFeatures.swift` | Settings, menus, shortcuts, swipes, tab moves, and split coordination |
| `Sources/NativeControls.swift` | Sidebar, drag targets, favorites, search, and new-tab interface |
| `Sources/SidebarResize.swift` | Native edge dragging, width limits, and deliberate collapse |
| `Sources/GlassSurface.swift` | Shared glass tint, highlights, rims, and accessibility fallback |
| `Sources/AppearanceTheme.swift` | Coordinated pastel palettes and lightweight browser previews |
| `Sources/FavoriteTile.swift` | Favorite tiles, hover/active feedback, and movement menus |
| `Sources/SidebarItemGlass.swift` | Sidebar item materials and accessibility fallback |
| `Sources/SiteControls.swift` | Domain address bar, copy feedback, zoom, and tab sound controls |
| `Sources/SettingsView.swift` | Settings, downloads, recent tabs, and page-error views |
| `Sources/BrowserState.swift` | Validated metadata and atomic storage |
| `Sources/Organization.swift` | Favorite/folder/tab/Space operations and gesture state |
| `Sources/Browser.mm` | CEF profiles, webpage views, split layout, downloads, permissions, and navigation |
| `Sources/Helper.cc` | Sandboxed Chromium subprocess entry point |
| `Sources/Bridge.h` | Narrow trusted C interface between Swift and Chromium |

CEF setup follows its official embedding examples. Licenses and Chromium credits are retained under `ThirdParty/` and in the app bundle.
