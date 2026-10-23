# Milestone 1 verification

Verified on the macOS Apple Silicon development host on October 22, 2026, using Electron 45.0.0, React 19.3.1, Vite 8.3.5, and strict TypeScript 7.0.2.

## Results

- Dependency installation completed. The official Electron runtime download was assembled from HTTP ranges due slow transfer rates and verified against the SHA-256 shipped in Electron's npm package before extraction.
- `npm run build` passed: TypeScript, Vite production assets, main-process bundle, and isolated preload bundle.
- `npm test` passed all fifteen tests covering URL/search resolution, forbidden schemes, IPC payload validation, sanitized lazy restoration, queued atomic persistence, and suggestion ranking.
- `node tests/electron.mjs` passed against the production build in real macOS Electron windows. It verifies native HTTP content, no website access to Node or the browser bridge, native keyboard events in both UI and webpage contents, retained form input/native view identity across switches, palette stacking above the retained website, sidebar bounds, 900×650 window resizing, navigation, closed-view destruction, lazy background restoration, metadata persistence, persistent cookies, and local storage.
- Both the root UI native bounds and CSS viewport measured 900×650 after resize. Fixed mode defaults to a 288px sidebar with 16px of frame spacing; hidden/hover modes use 8px on every side. Hover reveal leaves webpage bounds unchanged.
- `npm run build:icon` passed and generated PNG/ICNS assets from the original SVG. Icon generation waits for Chromium's first paint before capture.
- `npm run dev` launched successfully with Vite HMR and the narrow trusted IPC bridge. A native macOS keyboard check opened Cmd+T, accepted `example.com`, and displayed its public page in a separate Chromium native view.
- Light/dark home, light/dark palette, settings, and collapsed mint sidebar screenshots were visually inspected. Integration screenshots are generated in ignored `test-results/`.

The screenshots omit native macOS traffic lights because Playwright captures the UI web contents. Native accessibility inspection separately confirmed the close, fullscreen/zoom, and minimize controls exist.

## Initial diagnostic baseline

One successful local integration run recorded **395ms** from the main-process entry timestamp to window readiness. Main-process selection calls in that run recorded **3.49, 2.94, 2.72, 3.13, and 1.58ms**. These cover mixed new/restored/already-loaded view selection; they are not isolated end-to-end paint measurements. A separate Vite development launch recorded 538ms to window readiness.

These observations are a baseline for later measurement work, not a controlled cold/warm benchmark. OS caches, network, process launch overhead, and paint timing were not isolated. Memory and idle CPU were not profiled. No speed comparison with another browser is established.

## Remaining work

- The cookie/storage fixture proves persistence, not successful authentication with every identity provider. No real user credentials were entered.
- Permissions, downloads, crash recovery, pinning/reordering, and Space editing have implementation paths but need broader integration coverage before their respective later milestones are marked complete.
- Additional profiles/private browsing, configurable discarding, durable download history, and comprehensive performance instrumentation remain future work.
- The macOS packaging configuration and icons are present; DMG/ZIP production, code signing, notarization, release security review, and updater delivery were not verified.

## Arc-style shortcut and sidebar revision

The production build and all eight core tests passed after adding exact-modifier shortcut routing, sidebar preference migration, and persisted fixed/hover/hidden modes. The native suite additionally passed:

- Command-S from a focused website switches sidebar mode and changes the native page bounds.
- Native mouse input at the left edge reveals hover mode; native webpage mouse input dismisses it. Hidden mode does not expose a hover trigger.
- Option-Command-Down follows sidebar tab order. Control-Tab displays the recent-tab overlay above native pages and commits on Control release.
- Command-D toggles pinning. Option-Command-Right and Control-1 change Spaces. Shift-Command-T restores the last closed tab.
- The hidden preference survives restart. Settings' actual sidebar selector applies all three modes, and the Shortcuts reference is rendered.

Hover uses event-driven native mouse routing plus DOM/keyboard access to the reveal edge, with no pointer polling. The current sidebar floats above the website while revealed and leaves its viewport unchanged. Existing navigation, persistent storage, lazy restoration, and cleanup checks continue to pass. Full Arc feature or shortcut parity is not claimed for features Derivative does not implement.

## Folder and drag organization revision

Eleven core tests passed, including folder scoping, invalid cross-Space target rejection, ordering, safe ungrouping, sanitized restoration, and IPC validation. The actual Electron drag suite passed tab-to-folder, tab-to-pinned, drag-out-to-unpin, folder reorder, Space reorder, and tab-to-Space gestures. UI creation, rename, removal, collapse, and restoration of folder membership were verified.

The suite measured all default Space buttons at 32×32, their SVG icons at 18×18, and each icon centered at (16,16) within its button. The group's horizontal center matched the full sidebar's center within one CSS pixel. Website view identity and retained form input survived moving a tab between Spaces. Existing native view, shortcuts, hover behavior, persistent storage, and cleanup tests passed.

## Popup and sidebar transition revision

The production build, all eleven core tests, and the native Electron suite passed after introducing a preloaded transparent trusted chrome view. Assertions cover the popup being the topmost native child, the website remaining attached underneath, preserved unsaved textarea contents, hover reveal retaining the 8px page origin, the floating sidebar’s internal toggle, and removal of the native input layer after the exit transition. Hidden mode exposes no external expand toolbar. Existing folder/Space drag gestures, resizing, persistence, and lazy restoration continue to pass.

Modal and sidebar transitions use opacity/transform for 140–160ms, with a 180ms native detach grace period. Reduced-motion preferences shorten CSS motion. Window captures made through BrowserWindow.capturePage omit child native views on this host; they cannot establish composite rendering quality. Renderer screenshots and native stacking/bounds assertions are checked separately. Cross-renderer webpage blur is intentionally not used.

The floating sidebar revision adds an 8px inset, 16px corners, and a soft light/dark shadow. The native layer is 280px wide to include the 252px panel and its shadow. Native integration assertions check the panel geometry, full-height resizing, and unchanged website bounds during reveal. Settings names this mode “Floating on hover”; pinning retains the existing fixed sidebar mode.

Hover stability checks exercise the inset corners, shadow, late website crossing events, leaving and returning before dismissal, and reentering during the exit transition. Native hover routing owns dismissal, with a 220ms grace period; DOM panel-leave events no longer compete with it. Routine state updates preserve native view attachment and window-button visibility. Sidebar motion uses reversible CSS transitions.

## New tab search page revision

Command-T and the sidebar New Tab action now create an internal tab with an autofocus search page. The native suite checks creation count, URL submission reusing the same tab, configured search-engine suggestions, empty Command-L input, close/reopen behavior, preservation of the prior website view, and session restoration of empty tabs without extra website renderers. Core tests cover exact internal-address restoration, rejection of other privileged internal URLs, exclusion of internal tabs from website suggestions, and IPC validation. The isolated test windows disable physical mouse input so the host pointer cannot conflict with injected native coordinates.

The final production build, twelve core tests, and native Electron integration suite passed for the new tab revision. Light and dark new-tab screenshots were inspected.

## Sidebar frame, widths, favorites, and window behavior

The production build and fourteen core tests passed. Native integration passed all three width selections in both the React layout and live webpage bounds, real maximize/unmaximize behavior, the revealed sidebar’s top-left toggle, and restoration of the normal sidebar preference. The default fixed page origin is 304px; floating mode keeps the webpage at 8px. Native hover coverage scales with sidebar width.

The favorites UI was exercised through adding three favorites to reach twelve, enforcing the capacity limit, renaming, deleting, and restoring saved favorites. Geometry checks measured three equal columns, three default rows, four rows at capacity, 48px tile heights, and 20×20 icons. Light and dark screenshots were inspected. Existing tab, folder/Space drag, search, storage, and cleanup checks also passed.

The development runtime’s bundle display name was asserted as Derivative. Native macOS accessibility inspection independently showed “App: Derivative” and a “Derivative” application menu, with the normal sidebar visible. The branded runtime is a workspace-generated copy; signing clears only Finder metadata from that copy and preserves relative framework links.

## Full-screen sidebar control placement

Expanded windows reveal the floating sidebar through left-edge hover. The pin/toggle is the leftmost sidebar navigation control; back, forward, and reload are grouped to its right. The separate webpage overlay toggle and its native input surface were removed. Native checks cover actual full-screen entry/exit, edge-hover reveal without webpage resizing, control order, pinning while maximized, and restoration of normal-window bounds.

## Expanded-window padding slider

Maximized and full-screen pages retain the full canvas with an 8px outer frame. The sidebar slides from the left padding as a separate native overlay. Keeping it open no longer docks it into the page layout, and width changes leave the website viewport unchanged. Normal-window fixed mode continues to reserve sidebar space.

Regression checks compare native webpage bounds and the website’s actual inner viewport before/after keeping the expanded sidebar open, cover width changes and dismissal, and exercise native full-screen entry and exit. The React sidebar stays outside the page layout in expanded mode. A core test covers the separate decisions for visibility and layout reservation.

## Header spacing and menu reliability revision

The normal sidebar drag area is reduced to 30px; expanded sidebars use 8px, with navigation at y=16 including the frame inset. Expanded windows do not reserve a native traffic-light row. Footer controls no longer shrink offscreen, and favorites/editor areas scroll in short windows.

Trusted interaction ownership prevents hover dismissal while a sidebar menu/editor is active. Escape, outside clicks, and focus changes dismiss it and release ownership. A normal fixed-sidebar handoff detaches the old floating input layer immediately rather than retaining a duplicate through the exit grace period.

The build and fifteen core tests passed. Native integration passed repeated three-dot menu opening/selection, holding the menu across native pointer exits, Escape dismissal, immediate fixed-layout menu use after handoff, and footer menu access in a 900×480 window with twelve favorites. Existing browser, persistence, drag, and view-cleanup checks passed.

Native fullscreen entry was refused on this host in this run: no enter-full-screen event arrived, and isFullScreen remained false. An independent minimal stock Electron window reproduced the same refusal with fullscreen enabled. The suite explicitly reported that native-transition check as skipped; compact expanded-header and interaction behavior were verified using actual maximize/unmaximize. This run does not re-confirm native fullscreen entry/exit. Window mode handlers now use the explicit event’s state instead of re-reading transitional native flags.

## Fullscreen traffic-light reveal revision

Native fullscreen keeps the macOS window buttons enabled independently of sidebar visibility. macOS manages their top-edge reveal; no extra header row or webpage inset is introduced. Normal-window visibility and maximized-window layout retain their existing behavior.

The build and fifteen core tests passed. A focused Electron check simulates the native fullscreen flag and verifies that window buttons are enabled, routine preference updates never disable them, and the native webpage bounds stay unchanged. This policy check does not independently verify physical top-edge hover in a native fullscreen Space. Two broader native regression attempts stopped on Space icon dragging and maximize-state timing respectively; the full native suite is not reported as passing for this revision.

## Edge-to-edge expanded pages

Maximized and fullscreen webpage views now use the entire content bounds at x=0, y=0, with zero corner radius. The React New Tab and error canvas also remove padding, corner rounding, and frame shadows in expanded windows. The floating sidebar retains its own inset above the page; revealing, pinning, or resizing it does not change the page bounds. Normal windows restore their existing inset and rounded corners.

Build and fifteen core tests passed. A focused Electron check dispatches fullscreen entry/exit events and verifies the native webpage bounds, React New Tab geometry/styles, unchanged bounds with a revealed/pinned/resized sidebar, and normal-window restoration. This checks the application event/layout path without claiming a physical macOS fullscreen transition. Expanded geometry assertions also remain in the main native regression fixture.

## Native webpage edge reveal regression

Removing the outer frame meant the website view received left-edge mouse input instead of the root renderer. Its handler previously only kept an already revealed sidebar open. It now also opens the sidebar from the first 8px in window coordinates, without reserving that space or changing webpage bounds.

The focused regression is saved as `tests/fullscreen-layout.mjs`. It failed with “Sidebar did not reveal” before the change and passed afterward using mouse events sent directly to the native webpage. It covers opening, staying open across crossing events, dismissal, reopening, unchanged page bounds, pinning/resizing, New Tab geometry, and restoration. Fullscreen entry/exit events are simulated; no physical macOS fullscreen transition is claimed. Build and all fifteen core tests passed.

## Normal-window traffic-light row

The normal-window sidebar now places its toggle on the same row as the native traffic lights, to their right. The reserved native-control area is 72px; the toggle starts at window x=92 with center y=27, aligned with the native controls at x=20,y=20. Empty space in this row remains draggable and buttons retain their click targets. Expanded sidebar placement is unchanged.

Build and the focused Electron fixture passed. The fixture checks the native window-button position and toggle geometry at all three sidebar widths, verifies no overlap with back/forward/reload, and retains native webpage edge-hover coverage.

## Native traffic-light geometry restoration

Positioning the React toggle did not address AppKit resetting native traffic-light geometry when visibility changes. The chrome layer now reapplies the native x=20,y=20 position after showing the buttons and when moving from expanded controls back to the normal sidebar row. Fullscreen button visibility remains managed by the existing native policy.

Build passed. The focused Electron regression injects a native position reset during each show operation and verifies the sidebar position is restored on three repeated hide/show cycles, alongside the existing width/alignment and edge-hover checks. The native screenshot is partially obstructed by macOS's screen-sharing indicator over the traffic-light area; this check verifies native API ordering and layout geometry rather than claiming unobstructed visual confirmation.

## Confirmed tab opening, favorites, Space profiles, and split view

Cmd+T and the sidebar/File New Tab action now open the floating search panel without adding a tab or detaching the current webpage. Confirming a URL/search creates the tab; Escape/outside dismissal cancels. Existing-tab results include close buttons and a Current tab label. Closing a result keeps the search panel open, including when closing the active tab.

Favorites have a two-finger/right-click menu with Open, Open in new tab, Edit, Copy address, and Remove. Tiles support drag reordering with a drop indicator; order is persisted. Horizontal wheel gestures over fixed/floating sidebars switch Spaces, with one switch per gesture and vertical scrolling preserved.

Every Space uses a separate persistent Electron session. Personal retains its existing partition; other Spaces receive separate cookies, local storage, cache, and permission/download handling. Tabs moved across Spaces reload in the destination session. Website input and unsaved state remain intact when switching between Spaces without moving tabs.

Two same-Space website tabs can join a live split through the tab menu or the sidebar's drag-to-split target. Both native views remain attached and interactive. Pane focus updates navigation, title controls return to one page, and closing a pane/selecting another tab clears the pair safely. Popups and the floating sidebar stay above both native views. Split arrangements are transient; website tabs and their profiles persist.

Validation: build and all 17 unit tests passed. `node tests/interactions.mjs` passed confirmed creation/cancellation, closing active search results, favorite context editing/removal, grid drop ordering, sidebar swipe/momentum, cookie/local-storage isolation, native pane focus, split attachment/geometry/fullscreen layout, drag-to-split, exit/close cleanup, and restart persistence. Drag/swipe checks in this focused fixture inject DOM events; native website lifecycle, storage, cookies, and bounds are real. `node tests/fullscreen-layout.mjs` passed. The broader `node tests/electron.mjs` also passed, including native fullscreen entry/exit, actual HTML drag gestures for tab/folder/Space placement, shortcuts, session restoration, and view cleanup. Profile movement assertions now expect a destination-session renderer rather than reusing the original session.

## Favorite ownership and synchronized native development

Favorite-open actions adopt an existing matching tab in the active Space or create one tagged with the favorite ID. That identity survives in-site navigation and session restoration; the active grid tile gets a 2px inset accent outline, and owned pages are excluded from the ordinary sidebar rows. Removing a favorite preserves its live page and returns it to the normal tab list. Older saved sessions adopt one exact matching tab per favorite/Space. Explicitly organizing a favorite into the normal tab list clears its grid ownership.

The previous dev command hot-reloaded React but left Electron running its earlier action validator until a manual restart. It now watches native/shared TypeScript, rebuilds, gracefully quits to save metadata/cookies, and restarts Electron. Invalid-action diagnostics include the action type. A real source-file touch was used to verify automatic restart, with a new window-ready event and restored tabs. This addresses a demonstrated source/runtime mismatch path; no invalid-action rejection was reproduced in the current native build.

Build and 18 unit tests passed. `node tests/favorites.mjs` passed favorite adoption, no duplicate row, active highlight, navigation/reopen reuse, grid reorder, Space swipe, edge reveal, and contextual removal while retaining the native page. Both trusted surfaces were checked for error alerts after those actions. Gesture regression uses injected DOM/native events; it does not claim a physical trackpad gesture test.

## Clean identity, empty state, and tactile Space swipes

The app icon and in-app mark now use the same custom vector paths from `assets/brand.json`: a rounded geometric d with a small prime. The vector component replaces font glyphs on New Tab, launch, and About surfaces. App PNG/ICNS assets are regenerated from that geometry; the workspace runtime also carries the branded bundle icon and invalidates its cached clone when icon assets change.

Empty Spaces show their focused page search without duplicate sidebar search/Command-T rows. Existing tabs retain their normal sidebar search and New Tab controls.

Horizontal swipes translate the Space heading/tab area proportionally before the switch threshold. Short gestures spring back; committed gestures introduce the incoming Space from the matching side and settle over 220ms. Favorites, navigation, and Space icons remain anchored. Reduced-motion preferences suppress the translation while preserving switching and gesture locking.

Build and 18 unit tests passed. `tests/branding-swipe.mjs` verifies SVG geometry, empty-Space prompts, partial/reverse gesture motion, settled and cancelled gestures, anchored favorites, and reduced motion. `tests/interactions.mjs` also passed profile isolation, favorites, split views, and persistence. The generated icon and New Tab screenshot were visually inspected. Motion checks inject wheel events; a physical trackpad feel check remains user-dependent.

## Contrasting frosted sidebar and live grid preview

Sidebar gradients now have stronger tonal separation from both the frame and webpage, in light and dark themes. Translucent surfaces use a restrained 14px CSS backdrop blur/saturation and floating panels have softer, more distinct elevation. Backdrop filtering operates within the trusted renderer; it does not claim to sample pixels from a separate native website renderer. Website view bounds are unchanged.

Favorites dragging previews the actual three-column arrangement with animated tile translations and a translucent placeholder. Hit testing uses stable original cell positions, including scroll offsets, to avoid moving targets oscillating under the cursor. Metadata order stays unchanged until drop; cancellation restores the layout. A drop commits the preview position without replaying offsets after DOM order changes. The last grid slot is supported with a validated null append target.

Build and 19 unit tests passed. `tests/grid-preview.mjs` passed before-drop visual movement, unchanged saved state, cancellation, last-slot commit, final alignment of every tile, and light/dark appearances. `tests/favorites.mjs` passed ownership and sidebar gesture regression checks. Light and settled dark screenshots were visually inspected. Grid gestures in these focused checks use injected drag events rather than a physical mouse drag.

## Reuse search on empty pages

Cmd+T and Cmd+L now focus/select the existing New Tab input whenever the current Space has no active tab or its active tab is the internal New Tab. The native search-opening path clears any overlay and sends a focus event through the trusted preload instead of mounting another palette. Real websites keep their floating palette behavior.

Build and 19 unit tests passed. `tests/empty-search.mjs` covers repeated shortcuts, restored internal blank tabs, focus/selection, zero website views, no overlays, unchanged tab counts, and returning to a completely empty Space. `tests/interactions.mjs` covers zero-tab search reuse followed by normal website palette confirmation, cancellation, result closing, profiles, favorites, and split views.

## Tab-on-tab split targets and full-height fullscreen sidebar

Dragging a website tab over the center of another website tab previews a two-pane split. Dropping commits that explicit pair, even when a third tab was active. Top/bottom row edges reorder before/after the target. Self, invalid, internal-page, and cross-profile pairs cannot split. The pinned-area drag hint now reuses its existing label instead of adding a row that shifted targets during the gesture.

Expanded floating sidebars remove their top/bottom inset and corner rounding, retaining the configured width and existing horizontal position. Native webpage bounds remain edge-to-edge and unchanged during reveal.

Build and 19 unit tests passed. `tests/tab-drop-split.mjs` passed preview/cancellation, an actual Playwright HTML drag onto another tab, explicit pairing independent of active tab, retained textarea state, actual top/bottom edge drag reordering, and invalid-pair guards. `tests/fullscreen-layout.mjs` passed full-height/288px-width geometry, reveal/dismissal, pinning/resizing, and normal-window restoration. That fixture simulates fullscreen events rather than claiming a physical macOS transition.

## Joined sidebar row for split pairs

Split pairs now appear as one joined sidebar group with numbered 1/2 segments, favicons, titles, and active-pane highlighting. Their ordinary rows are hidden while split without changing pin/folder metadata. Selecting a segment focuses its live pane; hover close controls close that specific tab. The group context menu can separate the tabs. Exiting split restores the regular rows.

Build passed. `tests/tab-drop-split.mjs` additionally checks one joined group, segment numbers, no duplicate ordinary rows, segment focus while retaining two native views, contextual separation, and closing an individual segment. `tests/interactions.mjs` also passed. A screenshot of the joined row was visually inspected.

## Consistent fullscreen sidebar inset

The fullscreen floating sidebar again uses an 8px top/bottom/left inset and 14px corner radius, matching the normal sidebar surface. It retains its configured width; the website still fills the complete fullscreen viewport underneath. Build and the focused fullscreen-layout check passed, including exact margin/radius/width geometry, hover behavior, and unchanged webpage bounds.

## Sidebar color contrast without elevation

Removed outer shadows from fixed and floating sidebars and removed the floating surface's inset highlight. Sidebar palettes are darker in light mode; dark palettes now sit below the page surface in brightness. Rounded corners, margins, and subtle backdrop filtering remain. Build and the existing grid/appearance check passed.

## Reduced interaction overhead

State publication now sends changed sections with independent snapshots for the root and floating UI. Detached floating UI skips updates and catches up on reveal; unchanged history is omitted. Preload forwards patches across the isolated bridge after initial snapshot recovery. Duplicate post-action emissions/theme updates are removed, sidebar interaction ownership stays private, and UI-only settings/overlay/split dismissal avoids metadata saves. Native attachment and border-radius calls are cached. Popup presence retains exit state without an extra render on every state update, and favicon components skip unchanged renders.

The local native performance fixture uses 500 restored tabs (two loaded) and 2,000 history entries, measuring sequential automation action round trips. Before/after results from this machine:

| Operation | Median before → after | p95 before → after | Broadcasts before → after |
| --- | --- | --- | --- |
| 30 warm tab switches | 16.59 → 8.49ms | 24.85 → 25.33ms | 120 → 30 |
| 40 sidebar ownership changes | 7.64 → 0.33ms | 9.60 → 0.86ms | 80 → 0 |
| 20 palette open/close actions | 13.58 → 6.93ms | 30.51 → 35.38ms | 80 → 40 |

Tab switches transmitted zero unchanged history entries, versus 240,000 previously. After settling, the one-second idle sample produced zero state broadcasts. Assertions cover broadcast counts, unchanged history, and idle activity; timing thresholds are deliberately excluded. Tail latency did not consistently improve. These samples do not establish frame rates, website loading, CPU usage, or memory improvements. Search ranking remained unchanged after a separate local diagnostic measured a 1.31ms median and 3.52ms p95 for the large fixture.

Validation: build and all 22 unit tests passed. Focused native interaction/profile/split/persistence, fullscreen-layout, empty-search, and three-cycle floating-margin hover checks passed. Empty-search also reloads both trusted renderers to verify full-snapshot recovery. The broad native suite did not pass: separate attempts failed at floating-margin visibility and native maximize state. The isolated repeated margin fixture passed; OS transition timing remains an unresolved broad-suite limitation, so a complete native-suite pass is not claimed.

## Reliable Space gestures and compact controls

Space swipes now lock horizontal or vertical intent for the whole gesture, retaining diagonal continuation instead of discarding individual samples. Horizontal switching commits at 52px, suppresses same-direction momentum, accepts deliberate reversals without waiting for the quiet timer, and resets after 160ms of quiet. Wheel units are normalized. Visual follow updates are coalesced per animation frame, and listeners follow sidebar visibility. Vertical scrolling, editable fields, menus, and control-wheel gestures retain their normal behavior.

Space navigation no longer wraps at either end. Beyond the first/last Space (also with only one Space), movement meets capped exponential resistance with a small First/Last Space hint, then springs back. Animated content is clipped within its own viewport; favorites and bottom controls stay anchored. Bottom controls now have uniform 14px symbols in centered 27px buttons. Other Space symbols retain their existing size.

Build/typecheck and all 27 unit tests passed. Native branding/swipe checks passed diagonal samples, quick reversal, momentum suppression, both boundaries, spring-back, compact icon sizing, repeated floating-sidebar dismissal/reopen, and reduced motion. Native interaction checks passed profile isolation, favorites, split views, and persistence. The edge-feedback screenshot was visually inspected. Gesture tests inject wheel events and do not establish the feel of a physical trackpad on every device.

## Search respects the current Space's open tabs

Both New Tab search and the floating command palette now limit open-tab suggestions to the current Space. Their memoization includes active Space and tab identity, keeping results/current-tab labels correct even when the tabs array is unchanged. History behavior is unchanged.

Build and 28 unit tests passed, including empty/matching queries, identical URLs across profiles, switching Space, and an empty Space. The focused native interaction fixture additionally checks that an empty Work search excludes Personal's open tab and that Work's palette offers only its own matching tab.

## Floating sidebar top alignment

Expanded/fullscreen floating sidebars remove their top inset (y=0) while retaining the 8px side/bottom spacing and 14px corners. Normal-window geometry is unchanged. Build passed; the focused layout fixture checks the new top/height geometry, edge reveal/dismissal, and unchanged native webpage bounds. Fullscreen events in that fixture are simulated; macOS-owned menu-bar/notch regions are outside the renderer layout.

## Stable search input position

New Tab and floating search anchor their input independently of result count. Results grow downward within the remaining viewport and scroll in short windows; keyboard selection scrolls the chosen result into view. This replaces vertical centering of the whole changing panel, which moved the input as suggestions appeared or disappeared.

Build/typecheck passed. `tests/search-layout.mjs` passed fixed input coordinates across zero, one, and eight results, normal/short-window resizing, viewport containment, and keyboard scrolling for both search surfaces. Short-window screenshots were visually inspected. The native interaction fixture also passed confirmation/cancellation, result closing, profile isolation, favorites, and split views.

## Native foundation (historical baseline)

The `native/` implementation now uses SwiftUI controls, AppKit window composition, and sandbox-enabled CEF. The Electron implementation remains available. Native tab/Space state is validated and atomically saved in a separate `native-state.json`; website profiles use canonical direct-child `Space-<ID>` cache paths under the native root. CEF profile creation is asynchronous. Loaded native tab views retain form state when switched, and restored background tabs load on selection. Individual tab closure releases its native view without closing the parent window. Quit preserves tab metadata and releases request contexts before leaving the CEF event loop.

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

Favorites use balanced rows (including a 2×2 layout for four items and half-width tiles in two-item rows). Internal drags use a private in-process UTI. Grid gaps explicitly accept move operations; opening a favorite as an ordinary tab and adding a tab to favorites explicitly accept copy operations. Sidebar downloads open in a floating popover above the footer button, without changing the sidebar layout. The bottom options dots are removed, and the Space menu hides the native menu indicator. Joined split rows use website titles/icons and stay in their original pinned, Today, or folder section. Empty Spaces suppress history without deleting it.

The sidebar slides as one AppKit container, with explicit position animations and generation-checked completion. Rapid hide/reveal reversal preserves visibility and webpage bounds. The animation fixture measures actual presentation-layer positions; the geometry fixture checks matching top/bottom insets and native traffic-light alignment.
