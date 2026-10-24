# Native verification notes

Earlier implementation checks are retained in Git history. These notes describe the native app; historical measurements are labeled below.

## Native foundation (historical baseline)

The `native/` implementation now uses SwiftUI controls, AppKit window composition, and sandbox-enabled CEF. The earlier Electron implementation is retained in Git history. Native tab/Space state is validated and atomically saved in a separate `native-state.json`; website profiles use canonical direct-child `Space-<ID>` cache paths under the native root. CEF profile creation is asynchronous. Loaded native tab views retain form state when switched, and restored background tabs load on selection. Individual tab closure releases its native view without closing the parent window. Quit preserves tab metadata and releases request contexts before leaving the CEF event loop.

The native sidebar includes the three-column favorites grid, active favorite ownership, tab rows with pin/duplicate/close actions, compact Space controls, and per-Space dark pastel colors. Native search creates tabs on confirmation, scopes tab suggestions to the current Space, and reuses the embedded search in an empty Space. HTTP(S) popup links use the opener's profile. At that baseline, folders/drag organization, split view, editable favorites, swipe gestures, light themes/settings, and downloads were still pending. They are implemented in the feature update below.

Validation: the native build and ad-hoc signature verification passed. Pure Swift state checks passed selection, sanitization, restoration, URL rejection, and atomic metadata. Native rendering/input/navigation/quit checks passed. The tab/profile fixture passed lazy restoration, live form retention, individual view destruction, unchanged page bounds under search, empty-Space search reuse, per-Space cookie/local-storage isolation, popup profile ownership, restart persistence, and clean multi-tab quit. Controller actions are driven through a private, explicitly enabled local fixture directory; actual webpage state is checked through CDP. Automated windows refuse physical input and stay in the background. Native controls were additionally inspected through macOS accessibility/screenshots; these checks do not establish every physical gesture or sign-in flow.

The first native prototype measured 654.5 MiB versus 841.0 MiB Electron in summed process-tree RSS. After native tab/profile integration, the same one-page local fixture measured 693.4 MiB versus 854.8 MiB (about 19% lower). Each run used seven samples after three seconds settling and fresh profiles. Native Chromium was 156.0.8078.17; Electron Chromium was 156.0.8078.48. Shared pages can be counted more than once, native feature parity is incomplete, and patch versions differ. These are exploratory RSS totals, not unique physical footprint, energy measurements, multi-tab results, or guaranteed full-port savings.

Inactive native views are retained but detached from the window; the profile fixture additionally asserts that Chromium reports inactive pages as hidden while their form state survives reactivation. Test-only launches now use Chromium’s mock Keychain flag to avoid touching the user’s Keychain. Normal launches retain the platform behavior. Native quit also targets the root window when it is minimized or not the key window.

The initial post-integration visual check was blocked by a locked desktop. Later unlocked reviews verified the corrected sidebar and the feature update below.


## macOS feature update

The app is named Derivative throughout its bundle, menu, window titles, and About section. SwiftUI now includes editable/reorderable favorites, folders, tab drag organization, Space management and swipes with edge feedback, joined split rows, light/dark/system appearances, settings, download progress/actions, history and command suggestions, and the full shortcut reference. Chromium provides live split panes with a draggable divider, profile-safe cross-Space moves, downloads, explicit permission prompts, external-link confirmation, and page-error recovery.

Pure Swift state/organization/gesture tests pass. Native rendering and tab/profile fixtures pass. The feature fixture verifies real split attachment, retained forms, pane widths, settings without page movement, themes, recent/reopened tabs, downloaded bytes and cancellation, cross-Space cookie isolation after moves, scoped search, swipe bounds, Space operations, cookie/history/cache clearing, and shutdown. Cache clearing supplies an explicit CEF completion callback; its regression confirms cached responses are fetched again without terminating the app. Sidebar geometry tests include native title-bar relayout and the twelve-favorite minimum window.

Unlocked accessibility/screenshot inspection verified the new-tab page, sidebar, favorites, compact Space controls, and Settings/About over a live website. Controller-driven swipes and drag operations do not prove every physical trackpad/drop sequence; real website permissions, operating-system save dialogs, and all media/sign-in providers still need manual coverage. Earlier memory totals above predate this feature update and are not current measurements.


## Sidebar interaction refinements

Favorites use balanced rows (including a 2×2 layout for four items and half-width tiles in two-item rows). Internal drags use a private in-process UTI. Grid gaps explicitly accept move operations; opening a favorite as an ordinary tab and adding a tab to favorites explicitly accept copy operations. Sidebar downloads open in a floating popover above the footer button, without changing the sidebar layout. The bottom options dots are removed, and the Space menu hides the native menu indicator. Joined split rows use website titles/icons and stay in their original pinned, Today, or folder section. Empty Spaces suppress history until the user types, then show matching history in the regular floating search panel.

The sidebar slides as one AppKit container, with explicit position animations and generation-checked completion. Rapid hide/reveal reversal preserves visibility and webpage bounds. The animation fixture measures actual presentation-layer positions; the geometry fixture checks matching top/bottom insets and native traffic-light alignment.

Native window controls now use AppKit-created buttons in the content hierarchy, keeping their visible bounds and hit regions together instead of moving title-bar-owned views outside their parent. The sidebar fixture verifies each button's hit target, alignment after reveal/resize, and real minimize/restore. Typing in an empty Space promotes the existing query into the regular anchored search panel, hides the empty-page branding while searching, and offers matching history only after input. No tab is created until confirmation.

### Native webpage context menus

Chromium context targets now populate link, image, media, selection, and Inspect commands. Link/new-tab/split actions retain the opener’s Space profile. Save actions use the existing download handler; image copying uses Chromium’s image response and writes PNG data to the native clipboard. Web search uses the configured engine; image search opens Google Lens for HTTP(S) image URLs. Standard editing/spelling entries are retained. Separate browser/private windows, a mini-browser, and region capture are not implemented and are not advertised as menu commands.

`node native/scripts/context-menu.mjs` exercises actual Chromium context-menu events on linked images, editable text, selected text, and a JavaScript link. It verifies offered commands, new-tab and split ownership, saved image bytes, copied PNG data on an isolated test pasteboard, and developer tools opening/closing. Automated fixtures cancel the visible menu after collecting its model; selected commands use the same dispatch implementation as native menu clicks.

Fullscreen traffic lights appear in AppKit’s native top bar when it is revealed, while the fullscreen sidebar contains no traffic lights. Returning to a normal window restores the aligned sidebar controls and hides the native duplicates. The sidebar layout fixture checks both sets of controls and simulates a native title-bar reveal.

Fullscreen transitions hand control ownership to AppKit at `willEnter` and keep sidebar controls hidden until `didExit`. Resize callbacks during the animation cannot restore normal-window controls early. Failed transitions release the transition state. The sidebar fixture covers two enter/exit cycles with intermediate resizing, sidebar reveal, and failed-entry recovery.

The native address bar displays the domain (retaining development ports), keeps the full URL for editing/copying, and includes inline copy feedback and site controls. Zoom changes Chromium’s real page scale with a 25–300% clamp; mute belongs to each browser tab. Site controls pause floating-sidebar auto-hide while open and close on tab switches, other overlays, or sidebar toggling. Pure Swift checks cover address formatting, while the native feature fixture verifies real viewport scaling, zoom bounds/reset, per-tab mute state, and stable page bounds beneath the popover.

The native UI uses a shared glass surface treatment for the sidebar, favorites/address controls, search, settings, and popovers. The sidebar has an AppKit `NSVisualEffectView` with within-window blending; small controls use gradient fills without per-tile blur layers. Highlights and rims do not receive pointer events, and Reduce Transparency uses opaque backing surfaces. No outer sidebar shadow is added. Build, sidebar geometry/traffic-light checks, real slide/reversal checks, and the native feature fixture passed after this visual update.

Tab selection now covers the entire row label, including transparent padding and trailing space. The adjacent close target fills the same 34-point height with no gap. Tab, folder, and split controls provide hover and immediate press feedback. Sidebar geometry checks verify continuous target coverage at all three sidebar widths and multiple window sizes; a manual click on the empty leading padding also selected the expected tab. The native build, sidebar layout suite, and feature fixture passed after this interaction update.

## Media compatibility baseline and source-build preparation

The isolated media fixture confirms the official CEF engine decodes WebM/VP9 video and seeks, but rejects H.264/AAC MP4, AAC Web Audio decoding, and MP4 MSE. `media.mjs --require-proprietary` correctly fails on that engine. Synthetic fixtures contain locally generated test patterns and tones; tests count decoded frames, seek to 1.5 seconds, and inspect decoded AAC samples instead of accepting capability strings alone.

The app build now supports separate candidate output and a matching custom CEF distribution, keys wrapper/framework replacement on the actual framework SHA-256, and records engine provenance in the bundle. The pinned codec source-build workflow requires a candidate to pass all media checks and the normal browser smoke test before persisting engine selection. The existing official-engine app still builds and passes its rendering/input/navigation/quit smoke test. Full codec-enabled Chromium compilation is pending full Xcode installation; the source-build workflow and proprietary-codec success path have not yet been validated end to end. No H.264/AAC support is claimed for the currently running app.

## Native Liquid Glass surfaces

On macOS 26+, the sidebar, search, settings, and popovers use SwiftUI's system `glassEffect`, with restrained Space tinting. The sidebar no longer adds a second AppKit blur behind native glass. Older macOS versions keep the frosted AppKit/gradient fallback, and Reduce Transparency uses the opaque surface path. Favorite and address controls share their parent's material and retain lightweight fills. Neutral canvas colors and softer rims replace the stronger purple treatment.

The native build, sidebar geometry/full-row target/fullscreen checks, real slide/reversal checks, and browser feature fixture passed. The restarted app's sidebar and empty-page search were inspected visually. Older-system fallback and Reduce Transparency branches compile but were not separately exercised on another operating system or by changing the user's accessibility settings.

## Sidebar swipe lifecycle

Space swipes now follow AppKit's gesture phases rather than treating a brief pause as a new gesture. A trackpad gesture commits at most one Space change, retains its initial horizontal/vertical intent, and consumes horizontal momentum without turning it into another switch. A changed event without a sidebar gesture start cannot acquire a swipe midway through webpage scrolling. End/cancel events settle the preview, and unphased wheel events retain an inactivity fallback. Floating-sidebar auto-hide pauses while a gesture is active. First/last-Space hints overlay the scroll region instead of moving the footer and tab layout.

Pure state regressions cover pauses, reversals, outside-start changes, vertical intent, boundaries, and momentum. Native controller traces cover the same Space-switch failure sequences, continued accumulation across pauses, and unchanged webpage bounds under edge feedback. These traces exercise the recognizer/controller rather than a physical two-finger trackpad gesture.

Space transitions now move only the Space heading/tab section, keeping shared favorites, navigation, and footer icons stationary. A single clipped bitmap of the outgoing tab section is captured per gesture; it does not receive clicks or accessibility focus and is released after the paired 300 ms slide. The incoming section enters from the neighboring side using a continuous easing curve. Interrupted gestures settle back, new gestures supersede pending animation cleanup, and explicit Space selection cancels the decorative snapshot. Reduce Motion skips capture and large translations. Native feature checks verify snapshot creation/release, reverse-gesture interruption, selection cancellation, and stable page bounds; layout and sidebar reveal/reversal checks also pass. These checks do not constitute a physical trackpad animation review.

## Settings and coordinated palettes

Settings now opens to Appearance with code-drawn Light/Dark/System browser previews, selected-state feedback, and five pastel palette swatches. General groups existing browsing and data controls; Spaces uses inline swatches and editable names, while Downloads and Shortcuts have designed empty states and keycaps. Existing preference keys and color IDs remain compatible. Palette colors coordinate the sidebar accent, empty-page canvas, window background, and older-system glass fallback. Switching Spaces and editing their colors refreshes the window background without altering website content. The System preview uses macOS appearance independently of the app's manual override.

The native build, browser feature/theme checks, and sidebar geometry/fullscreen checks passed. Accessibility and screenshots verified the redesigned Appearance panel and selecting Light mode. Final spacing refinements compact the previews and keep native scroll indicators available for shorter windows. Screenshot inspection does not establish every accessibility configuration or control across all operating systems.


## Space favorites and search styling

Favorites now belong to individual Spaces, with a twelve-item limit per collection. Version 1 shared favorites are copied into each existing Space, preserving order and rebinding open favorite tabs; the original metadata is backed up before conversion. New Spaces start empty. Dragging a favorite onto a Space icon or using its Move to Space menu transfers the bookmark while leaving a live webpage in its original profile as a regular tab. Favorites now slide with the Space's tab section; navigation and footer controls stay stationary.

Favorite tiles, tab rows, and folders use native item glass with hover/selected tinting and older-system/Reduce Transparency fallback. An enclosing GlassEffectContainer caused a reproducible SwiftUI focus-navigation hang during integration testing and was removed; the individual glass styling remains. Search has a readable glass-backed surface, tinted selection, favicon tiles, keyboard hints, and placement centered over the page canvas. The address target includes a search glyph and immediate press feedback.

Pure Swift checks passed for migration, backup bytes, idempotent sanitization, independent edits, per-Space capacity, profile-safe movement, and persistence. The native build and features, tabs/profiles, sidebar layout, and sidebar animation suites passed, including drag-delegate movement between Spaces and existing swipe snapshot cleanup. The restarted app's favorite movement menu and Light-mode search were inspected. Physical trackpad dragging and older-system accessibility fallbacks were not separately exercised in this pass.


## Native-only repository cleanup

The Electron/React application, its tests and build scripts, Vite/TypeScript configuration, and obsolete memory-comparison fixture were removed. The npm manifest now contains only pinned Playwright test tooling; `npm run build` builds the native app. Logo and compiled icon assets remain available. Earlier implementation source and checks are retained in Git history.

A fresh `npm ci --ignore-scripts`, `npm test` (Swift state and three engine package checks), the native build, and all seven integration fixtures passed after cleanup. The media fixture remains a baseline check: WebM decoded and sought successfully, while H.264/AAC and MP4 MSE remain unsupported by the current engine. Relative documentation links and `git diff --check` also passed. No native browser source changed in this cleanup.


## Pinned sidebar sizing in expanded windows

Explicitly pinning the sidebar now reserves its width in maximized/fullscreen windows, matching normal-window fixed behavior. Unpinning restores edge-to-edge webpage bounds; hover reveal remains an overlay. The native build, sidebar layout and animation fixtures, and feature fixture passed. Geometry checks cover all three widths, and the feature fixture verifies both live split panes fit the remaining page area. Derivative was restarted with the updated build.
